"""svcdash/pve.py — Proxmox VE 虚拟机状态同步模块

从本地 PVE 集群 API (https://192.168.3.10:8006) 采集 Windows11、DEBIAN 等虚拟机运行状态、
资源利用率 (CPU/内存/磁盘) 与 IP 地址。
支持：
1. 内存缓存 (TTL 15s) 与自动 Ticket 续签 / 401 恢复
2. 提取 Guest Agent IP 及脱敏
3. 纯 Python 标准库 (urllib.request + ssl)，零第三方依赖
4. 公网静态快照脱敏导出
"""

import json
import os
import re
import ssl
import threading
import time
import urllib.parse
import urllib.request
from svcdash.i18n import t

PVE_URL = os.environ.get("PVE_URL", "https://192.168.3.10:8006").rstrip("/")
PVE_USER = os.environ.get("PVE_USER", "root@pam")
PVE_PASS = os.environ.get("PVE_PASS", "cheche126")
PVE_NODE = os.environ.get("PVE_NODE", "pve")

_cache_lock = threading.Lock()
_vms_cache = (0.0, None)  # (timestamp, data)
_ticket_lock = threading.Lock()
_cached_ticket = None
_cached_csrf = None
_cached_ticket_time = 0.0

# 忽略 PVE 自签名 SSL 证书
_ssl_ctx = ssl.create_default_context()
_ssl_ctx.check_hostname = False
_ssl_ctx.verify_mode = ssl.CERT_NONE


def _get_ticket(force=False):
    """获取或刷新 PVE API Ticket (默认 2 小时有效，内部按 1 小时自动续签)。"""
    global _cached_ticket, _cached_csrf, _cached_ticket_time
    now = time.time()
    with _ticket_lock:
        if not force and _cached_ticket and (now - _cached_ticket_time < 3600):
            return _cached_ticket, _cached_csrf

        url = f"{PVE_URL}/api2/json/access/ticket"
        data = urllib.parse.urlencode({"username": PVE_USER, "password": PVE_PASS}).encode("utf-8")
        req = urllib.request.Request(url, data=data, headers={"User-Agent": "svc-dashboard/1.0"})
        try:
            with urllib.request.urlopen(req, context=_ssl_ctx, timeout=6) as resp:
                res = json.loads(resp.read().decode("utf-8", "ignore"))
                _cached_ticket = res["data"]["ticket"]
                _cached_csrf = res["data"]["CSRFPreventionToken"]
                _cached_ticket_time = now
                return _cached_ticket, _cached_csrf
        except Exception as e:
            # 若续签失败但旧 ticket 还在且不到 2 小时，尝试继续用
            if _cached_ticket and (now - _cached_ticket_time < 7000):
                return _cached_ticket, _cached_csrf
            raise RuntimeError(f"PVE login failed: {e}")


def _pve_request(path, retry_auth=True):
    """向 PVE 发送带 Ticket Cookie 的 GET 请求。"""
    ticket, csrf = _get_ticket()
    url = f"{PVE_URL}{path}"
    req = urllib.request.Request(url, headers={
        "User-Agent": "svc-dashboard/1.0",
        "Cookie": f"PVEAuthCookie={ticket}",
        "CSRFPreventionToken": csrf or "",
    })
    try:
        with urllib.request.urlopen(req, context=_ssl_ctx, timeout=6) as resp:
            return json.loads(resp.read().decode("utf-8", "ignore")).get("data")
    except urllib.error.HTTPError as e:
        if e.code == 401 and retry_auth:
            _get_ticket(force=True)
            return _pve_request(path, retry_auth=False)
        raise


def _fmt_uptime(sec):
    """格式化运行时长: 63 天 23:38:36 或 23:38:36。"""
    if not sec or sec <= 0:
        return ""
    sec = int(sec)
    days = sec // 86400
    rem = sec % 86400
    hours = rem // 3600
    mins = (rem % 3600) // 60
    secs = rem % 60
    time_str = f"{hours:02d}:{mins:02d}:{secs:02d}"
    if days > 0:
        return f"{days} 天 {time_str}"
    return time_str


def get_pve_vms(force=False):
    """获取所有受管 QEMU 虚拟机的完整运行状态与指标。"""
    global _vms_cache
    now = time.time()
    with _cache_lock:
        if not force and _vms_cache[1] is not None:
            ts, val = _vms_cache
            if now - ts < 15:
                return val

    try:
        # 1. 查询集群虚拟机列表
        res_list = _pve_request("/api2/json/cluster/resources?type=vm") or []
        qemu_list = [v for v in res_list if v.get("type") == "qemu"]
        # 保证 Windows11 (101) 和 DEBIAN (103) 按 vmid 升序
        qemu_list.sort(key=lambda x: int(x.get("vmid", 0)))

        vms = []
        for q in qemu_list:
            vmid = q.get("vmid")
            node = q.get("node") or PVE_NODE
            name = q.get("name") or f"VM-{vmid}"

            # 2. 查询当前单机详情
            try:
                detail = _pve_request(f"/api2/json/nodes/{node}/qemu/{vmid}/status/current") or {}
            except Exception:
                detail = q

            status = detail.get("status") or q.get("status") or "stopped"
            uptime = detail.get("uptime") or q.get("uptime") or 0
            cpus = detail.get("cpus") or q.get("maxcpu") or 1
            cpu_usage_raw = detail.get("cpu") or q.get("cpu") or 0.0  # 0.0 ~ 1.0 (占总分配比)
            cpu_pct = round(cpu_usage_raw * 100, 2)

            maxmem = detail.get("maxmem") or q.get("maxmem") or 0
            mem = detail.get("mem") or q.get("mem") or 0
            mem_pct = round((mem / maxmem * 100), 2) if maxmem > 0 else 0.0

            memhost = detail.get("memhost") or q.get("memhost") or 0
            maxdisk = detail.get("maxdisk") or q.get("maxdisk") or 0

            # 3. 查询网络与 IP
            ips = []
            has_agent = False
            if status == "running":
                try:
                    net_info = _pve_request(f"/api2/json/nodes/{node}/qemu/{vmid}/agent/network-get-interfaces")
                    if isinstance(net_info, dict) and "result" in net_info:
                        has_agent = True
                        for iface in net_info["result"]:
                            if iface.get("name") == "lo":
                                continue
                            for addr in iface.get("ip-addresses", []):
                                ip = addr.get("ip-address")
                                if ip and not ip.startswith("127.") and not ip.startswith("fe80::"):
                                    # 过滤 docker/bridge 网段
                                    if not ip.startswith("172.17.") and not ip.startswith("172.18.") and not ip.startswith("172.19.") and not ip.startswith("172.20.") and not ip.startswith("172.21."):
                                        ips.append(ip)
                except Exception:
                    pass

            # 若未拿到 guest agent IP，尝试使用 tags
            tags = q.get("tags") or detail.get("tags") or ""
            if not ips and tags:
                tag_ips = [t.strip() for t in tags.split(",") if re.match(r"^\d{1,3}(?:\.\d{1,3}){3}$", t.strip())]
                ips.extend(tag_ips)

            # 控制台直达 URL
            pve_console_url = f"{PVE_URL}/#v1:0:=qemu%2F{vmid}:4:=notes::::::=notes"

            vms.append({
                "vmid": vmid,
                "name": name,
                "status": status,
                "uptime": uptime,
                "uptime_str": _fmt_uptime(uptime),
                "ha": "none",
                "node": node,
                "cpus": cpus,
                "cpu_usage": cpu_pct,
                "mem_used": mem,
                "mem_total": maxmem,
                "mem_percent": mem_pct,
                "mem_host": memhost,
                "boot_disk": maxdisk,
                "ips": ips,
                "has_guest_agent": has_agent,
                "pve_url": pve_console_url,
            })

        data = {
            "ok": True,
            "updated": now,
            "pve_host": urllib.parse.urlparse(PVE_URL).hostname or "192.168.3.10",
            "vms": vms,
        }
        with _cache_lock:
            _vms_cache = (now, data)
        return data

    except Exception as e:
        with _cache_lock:
            if _vms_cache[1] is not None:
                old_data = dict(_vms_cache[1])
                old_data["stale"] = True
                return old_data
        return {
            "ok": False,
            "error": str(e),
            "updated": now,
            "pve_host": "192.168.3.10",
            "vms": [],
        }


def sanitize_pve_vms_for_public(vms_data: dict, lang: str = "zh") -> dict:
    """脱敏公开静态快照中的 PVE 虚拟机数据。
    保留 VM 名称、状态、CPU、内存百分比、磁盘和运行时长；
    内网 IP 与 IPv6 脱敏，防止公开个人家庭网段与公网 IPv6 痕迹。
    """
    clean = {
        "ok": bool(vms_data.get("ok")),
        "updated": vms_data.get("updated") or time.time(),
        "pve_host": "[PVE-HOST]",
        "vms": [],
    }
    for v in vms_data.get("vms", []):
        ips = []
        for ip in v.get("ips", []):
            if ":" in ip:
                # IPv6 仅保留前缀
                parts = ip.split(":")
                ips.append(f"{parts[0]}:****::*")
            else:
                # 隐藏私有 IP 主机位
                parts = ip.split(".")
                if len(parts) == 4:
                    ips.append(f"{parts[0]}.{parts[1]}.{parts[2]}.*")
                else:
                    ips.append("127.0.0.1")

        cv = dict(v)
        cv["ips"] = ips
        cv["pve_url"] = "https://127.0.0.1:8006/"
        clean["vms"].append(cv)
    return clean


_detail_cache = {}  # vmid -> (timestamp, data)


def get_pve_vm_detail(vmid, force=False):
    """获取单台虚拟机的完整详细配置、RRD 性能趋势图表数据、硬件清单、快照与任务历史。"""
    global _detail_cache
    vmid = str(vmid)
    now = time.time()
    with _cache_lock:
        if not force and vmid in _detail_cache:
            ts, val = _detail_cache[vmid]
            if now - ts < 15:
                return val

    try:
        node = PVE_NODE
        status = _pve_request(f"/api2/json/nodes/{node}/qemu/{vmid}/status/current") or {}
        config = _pve_request(f"/api2/json/nodes/{node}/qemu/{vmid}/config") or {}
        rrd = _pve_request(f"/api2/json/nodes/{node}/qemu/{vmid}/rrddata?timeframe=hour") or []
        snaps = _pve_request(f"/api2/json/nodes/{node}/qemu/{vmid}/snapshot") or []
        tasks = _pve_request(f"/api2/json/nodes/{node}/tasks?vmid={vmid}") or []

        # 整理硬件设备 (磁盘、光驱、网卡、固件)
        disks = []
        nics = []
        for k in sorted(config.keys()):
            v = str(config[k])
            if any(k.startswith(p) for p in ("scsi", "sata", "virtio", "ide", "efidisk", "tpmstate")):
                disks.append({"key": k, "value": v})
            elif k.startswith("net"):
                nics.append({"key": k, "value": v})

        # 整理 RRD 曲线点 (最多 60 点，保留时间戳与关键指标)
        rrd_points = []
        for p in rrd:
            if p.get("time"):
                rrd_points.append({
                    "time": p["time"],
                    "cpu": round((p.get("cpu") or 0.0) * 100, 2),
                    "mem": p.get("mem") or 0,
                    "maxmem": p.get("maxmem") or 0,
                    "memhost": p.get("memhost") or 0,
                    "netin": round(p.get("netin") or 0.0, 1),
                    "netout": round(p.get("netout") or 0.0, 1),
                    "diskread": round(p.get("diskread") or 0.0, 1),
                    "diskwrite": round(p.get("diskwrite") or 0.0, 1),
                })

        # 整理快照
        clean_snaps = []
        for s in snaps:
            clean_snaps.append({
                "name": s.get("name") or "",
                "description": s.get("description") or "",
                "snaptime": s.get("snaptime") or 0,
                "vmstate": bool(s.get("vmstate")),
                "running": bool(s.get("running")),
            })

        # 整理最近 20 条任务历史
        clean_tasks = []
        for t in tasks[:20]:
            clean_tasks.append({
                "type": t.get("type") or "",
                "status": t.get("status") or "OK",
                "user": t.get("user") or "",
                "starttime": t.get("starttime") or 0,
                "endtime": t.get("endtime") or 0,
            })

        # 提取 Guest Agent IP
        ips = []
        has_agent = False
        if status.get("status") == "running":
            try:
                net_info = _pve_request(f"/api2/json/nodes/{node}/qemu/{vmid}/agent/network-get-interfaces")
                if isinstance(net_info, dict) and "result" in net_info:
                    has_agent = True
                    for iface in net_info["result"]:
                        if iface.get("name") == "lo":
                            continue
                        for addr in iface.get("ip-addresses", []):
                            ip = addr.get("ip-address")
                            if ip and not ip.startswith("127.") and not ip.startswith("fe80::"):
                                if not ip.startswith("172.17.") and not ip.startswith("172.18.") and not ip.startswith("172.19.") and not ip.startswith("172.20.") and not ip.startswith("172.21."):
                                    ips.append(ip)
            except Exception:
                pass

        if not ips:
            tags = config.get("tags") or status.get("tags") or ""
            if tags:
                tag_ips = [t.strip() for t in tags.split(",") if re.match(r"^\d{1,3}(?:\.\d{1,3}){3}$", t.strip())]
                ips.extend(tag_ips)

        data = {
            "ok": True,
            "vmid": vmid,
            "name": config.get("name") or status.get("name") or f"VM-{vmid}",
            "status": status.get("status") or "stopped",
            "uptime": status.get("uptime") or 0,
            "uptime_str": _fmt_uptime(status.get("uptime") or 0),
            "node": node,
            "ha": "none" if not status.get("ha", {}).get("managed") else "managed",
            "cpus": status.get("cpus") or config.get("cores") or 1,
            "cpu_usage": round((status.get("cpu") or 0.0) * 100, 2),
            "mem_used": status.get("mem") or 0,
            "mem_total": status.get("maxmem") or (int(config.get("memory", 0)) * 1024 * 1024),
            "mem_host": status.get("memhost") or 0,
            "boot_disk": status.get("maxdisk") or 0,
            "ips": ips,
            "has_guest_agent": has_agent,
            "pve_url": f"{PVE_URL}/#v1:0:=qemu%2F{vmid}:4:=notes::::::=notes",
            "hardware": {
                "cores": config.get("cores") or status.get("cpus") or 1,
                "sockets": config.get("sockets") or 1,
                "cpu_type": config.get("cpu") or "kvm64",
                "memory_mb": config.get("memory") or 0,
                "balloon": config.get("balloon"),
                "bios": config.get("bios") or "seabios",
                "machine": config.get("machine") or "pc",
                "disks": disks,
                "nics": nics,
            },
            "options": {
                "onboot": bool(config.get("onboot")),
                "boot_order": config.get("boot") or "",
                "ostype": config.get("ostype") or "other",
                "agent": config.get("agent") or "",
            },
            "rrd": rrd_points,
            "snapshots": clean_snaps,
            "tasks": clean_tasks,
            "updated": now,
        }

        with _cache_lock:
            _detail_cache[vmid] = (now, data)
        return data

    except Exception as e:
        with _cache_lock:
            if vmid in _detail_cache:
                old = dict(_detail_cache[vmid][1])
                old["stale"] = True
                return old
        return {
            "ok": False,
            "error": str(e),
            "vmid": vmid,
            "updated": now,
        }


def sanitize_pve_vm_detail_for_public(detail: dict, lang: str = "zh") -> dict:
    """脱敏公开静态快照中的虚拟机详情。
    隐藏内网私有真实主机 IP 与网卡 MAC 地址，保留指标趋势曲线、硬件规格、快照与任务概要。
    """
    clean = dict(detail)
    clean["pve_url"] = "https://127.0.0.1:8006/"

    # 脱敏 IP
    ips = []
    for ip in detail.get("ips", []):
        if ":" in ip:
            parts = ip.split(":")
            ips.append(f"{parts[0]}:****::*")
        else:
            parts = ip.split(".")
            if len(parts) == 4:
                ips.append(f"{parts[0]}.{parts[1]}.{parts[2]}.*")
            else:
                ips.append("127.0.0.1")
    clean["ips"] = ips

    # 脱敏硬件里的 MAC 地址
    hw = dict(detail.get("hardware") or {})
    clean_nics = []
    for nic in hw.get("nics", []):
        val = nic.get("value", "")
        # virtio=BC:24:11:60:6D:9C,... -> virtio=BC:24:11:*:*:*,...
        val = re.sub(r"([0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}):[0-9A-Fa-f:]+", r"\1:*:*:*", val)
        clean_nics.append({"key": nic.get("key"), "value": val})
    hw["nics"] = clean_nics
    clean["hardware"] = hw

    # 脱敏任务用户
    clean_tasks = []
    for t in detail.get("tasks", []):
        ct = dict(t)
        if ct.get("user"):
            ct["user"] = "root"
        clean_tasks.append(ct)
    clean["tasks"] = clean_tasks

    return clean
