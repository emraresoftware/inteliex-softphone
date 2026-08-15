#!/usr/bin/env python3

import argparse
import sys

import paramiko
from paramiko.ssh_exception import BadAuthenticationType


def main():
    parser = argparse.ArgumentParser(description="Parola ile uzak komut calistirir.")
    parser.add_argument("--host", required=True)
    parser.add_argument("--user", required=True)
    parser.add_argument("--password", required=True)
    parser.add_argument("--command", required=True)
    parser.add_argument("--port", type=int, default=22)
    args = parser.parse_args()

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    try:
        client.connect(
            hostname=args.host,
            port=args.port,
            username=args.user,
            password=args.password,
            timeout=10,
            look_for_keys=False,
            allow_agent=False,
        )
        _, stdout, stderr = client.exec_command(args.command)
        out = stdout.read().decode("utf-8", errors="replace")
        err = stderr.read().decode("utf-8", errors="replace")
        exit_status = stdout.channel.recv_exit_status()
        if out:
            sys.stdout.write(out)
        if err:
            sys.stderr.write(err)
        raise SystemExit(exit_status)
    except BadAuthenticationType as exc:
        allowed = ", ".join(exc.allowed_types)
        sys.stderr.write(
            f"Parola ile giris reddedildi. Sunucunun izin verdigi yontemler: {allowed}\n"
        )
        raise SystemExit(2)
    finally:
        client.close()


if __name__ == "__main__":
    main()