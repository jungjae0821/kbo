"""Publish one gzip-compressed, read-only season object using OCI CLI credentials.

Run in OCI Cloud Shell: python3 deploy_oci_dataset.py --compartment-id <OCID>
No VM, database, access key, bucket listing, or version history is provisioned.
"""

import argparse
import gzip
import hashlib
import json
import subprocess
import tempfile
import urllib.request
from pathlib import Path

SOURCE_COMMIT = "70a5478017abbfce11ac116774338226c7bd9564"
SOURCE_URL = (
    "https://raw.githubusercontent.com/jungjae0821/kbo/"
    f"{SOURCE_COMMIT}/app/assets/data/season_dataset.json"
)
COMPACT_SHA256 = "5ab91f5f7a7e7235ad88a9a89e6034b67f0f653735211a1a03d946785b858413"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compartment-id", required=True)
    parser.add_argument("--bucket", default="kbo-season-data")
    parser.add_argument("--region", default="ap-osaka-1")
    args = parser.parse_args()

    def cli(*parts):
        return subprocess.check_output(
            ["oci", "--region", args.region, *parts], text=True
        ).strip()

    with urllib.request.urlopen(SOURCE_URL, timeout=30) as response:
        dataset = json.load(response)
    compact = json.dumps(dataset, ensure_ascii=False, separators=(",", ":")).encode()
    if hashlib.sha256(compact).hexdigest() != COMPACT_SHA256:
        raise ValueError("Pinned source differs from the locally validated dataset")
    compressed = gzip.compress(compact, mtime=0)
    namespace = cli("os", "ns", "get", "--query", "data", "--raw-output")
    # Creation must succeed: never change an existing bucket's visibility.
    cli(
        "os", "bucket", "create", "--compartment-id", args.compartment_id,
        "--name", args.bucket, "--public-access-type", "ObjectReadWithoutList",
        "--storage-tier", "Standard", "--versioning", "Disabled",
    )
    with tempfile.TemporaryDirectory(prefix="kbo-publish-") as directory:
        path = Path(directory) / "season_dataset.json.gz"
        path.write_bytes(compressed)
        cli(
            "os", "object", "put", "--bucket-name", args.bucket,
            "--name", "season_dataset.json", "--file", str(path),
            "--content-type", "application/json; charset=utf-8",
            "--content-encoding", "gzip", "--cache-control", "public,max-age=3600",
            "--no-multipart", "--verify-checksum",
        )
    print(json.dumps({
        "url": f"https://objectstorage.{args.region}.oraclecloud.com/n/{namespace}/b/{args.bucket}/o/season_dataset.json",
        "stored_bytes": len(compressed),
        "decoded_bytes": len(compact),
        "decoded_sha256": COMPACT_SHA256,
        "source_commit": SOURCE_COMMIT,
        "bucket_access": "ObjectReadWithoutList",
        "versioning": "Disabled",
    }, indent=2))


if __name__ == "__main__":
    main()
