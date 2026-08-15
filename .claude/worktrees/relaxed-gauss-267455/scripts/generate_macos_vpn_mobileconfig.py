#!/usr/bin/env python3

import argparse
import json
import plistlib
import uuid
from pathlib import Path


def build_payload(config):
    payload_uuid = str(uuid.uuid4()).upper()
    content_uuid = str(uuid.uuid4()).upper()
    display_name = config.get("name", "Dergah VPN")
    server = config["server"]
    username = config["username"]
    password = config["password"]
    shared_secret = config["shared_secret"]

    return {
        "PayloadType": "Configuration",
        "PayloadVersion": 1,
        "PayloadIdentifier": "com.dergah.vpn.profile",
        "PayloadUUID": payload_uuid,
        "PayloadDisplayName": display_name,
        "PayloadOrganization": "Dergah",
        "PayloadRemovalDisallowed": False,
        "PayloadContent": [
            {
                "PayloadType": "com.apple.vpn.managed",
                "PayloadVersion": 1,
                "PayloadIdentifier": "com.dergah.vpn.profile.managed",
                "PayloadUUID": content_uuid,
                "PayloadDisplayName": display_name,
                "UserDefinedName": display_name,
                "VPNType": "L2TP",
                "PPP": {
                    "AuthName": username,
                    "AuthPassword": password,
                    "CommRemoteAddress": server,
                },
                "IPSec": {
                    "AuthenticationMethod": "SharedSecret",
                    "SharedSecret": shared_secret,
                },
            }
        ],
    }


def main():
    parser = argparse.ArgumentParser(description="VPN JSON config'den macOS mobileconfig uretir.")
    parser.add_argument(
        "--config",
        default="/Users/emre/Dergah/data/config/vpn.local.json",
        help="JSON config yolu",
    )
    parser.add_argument(
        "--output",
        default="/Users/emre/Dergah/data/config/dergah-vpn.mobileconfig",
        help="Olusturulacak mobileconfig yolu",
    )
    args = parser.parse_args()

    config_path = Path(args.config)
    output_path = Path(args.output)

    with config_path.open("r", encoding="utf-8") as handle:
        config = json.load(handle)

    required_fields = ["server", "username", "password", "shared_secret"]
    missing = [field for field in required_fields if not config.get(field)]
    if missing:
        raise SystemExit(f"Eksik alanlar: {', '.join(missing)}")

    payload = build_payload(config)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("wb") as handle:
        plistlib.dump(payload, handle, fmt=plistlib.FMT_XML)

    print(f"Mobileconfig olusturuldu: {output_path}")
    local_network = config.get("local_network", {})
    network_range = local_network.get("range")
    if network_range:
        print(f"VPN ic ag araligi: {network_range}")
    preferred_hosts = config.get("preferred_hosts", {})
    m5_host = preferred_hosts.get("m5_host")
    if m5_host:
        print(f"M5 host adayi: {m5_host}")
    coordinator_host = preferred_hosts.get("coordinator_host")
    if coordinator_host:
        print(f"Coordinator host adayi: {coordinator_host}")


if __name__ == "__main__":
    main()