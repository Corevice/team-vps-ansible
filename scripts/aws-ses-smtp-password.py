#!/usr/bin/env python3
"""AWS IAM secret access key → SES SMTP password 変換 (HMAC-SHA256 + base64)
公式手順: https://docs.aws.amazon.com/ses/latest/dg/smtp-credentials.html
"""
import hmac
import hashlib
import base64
import sys

DATE = "11111111"
SERVICE = "ses"
TERMINAL = "aws4_request"
MESSAGE = "SendRawEmail"
VERSION = 0x04


def sign(key, msg):
    return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()


def calculate_key(secret_access_key, region):
    signature = sign(("AWS4" + secret_access_key).encode("utf-8"), DATE)
    signature = sign(signature, region)
    signature = sign(signature, SERVICE)
    signature = sign(signature, TERMINAL)
    signature = sign(signature, MESSAGE)
    signature_and_version = bytes([VERSION]) + signature
    smtp_password = base64.b64encode(signature_and_version)
    return smtp_password.decode("utf-8")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: aws-ses-smtp-password.py <SECRET_ACCESS_KEY> <REGION>", file=sys.stderr)
        sys.exit(1)
    print(calculate_key(sys.argv[1], sys.argv[2]))
