"""
Generates one QR code PNG per person from a CSV of users, for printing onto
ID badges. This is NOT part of the Flutter app - run it separately whenever
you have a new/updated roster.

Usage:
    pip install qrcode[pil]
    python generate_qr_codes.py users.csv output_folder/

CSV must have a header row with at least an 'id' column, e.g.:
    id,name,role,group
    U001,Ada Okafor,Volunteer,Team A
    U002,Bola Adeyemi,Guest,Team B

Each QR code encodes ONLY the id (e.g. "U001") - the app looks up
name/role/group locally, so keep QR content short for reliable, fast scans.
"""

import csv
import sys
import os
import qrcode


def generate(csv_path: str, output_dir: str) -> None:
    os.makedirs(output_dir, exist_ok=True)

    with open(csv_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        if "id" not in (reader.fieldnames or []):
            raise ValueError("CSV must contain an 'id' column")

        count = 0
        for row in reader:
            user_id = row["id"].strip()
            if not user_id:
                continue

            qr = qrcode.QRCode(
                version=1,
                error_correction=qrcode.constants.ERROR_CORRECT_M,
                box_size=10,
                border=4,
            )
            qr.add_data(user_id)
            qr.make(fit=True)
            img = qr.make_image(fill_color="black", back_color="white")

            # Filename includes id (and name, if present) for easy sorting
            # while printing/matching to badges.
            name_part = row.get("name", "").strip().replace(" ", "_")
            filename = f"{user_id}_{name_part}.png" if name_part else f"{user_id}.png"
            img.save(os.path.join(output_dir, filename))
            count += 1

    print(f"Generated {count} QR code(s) in '{output_dir}'")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python generate_qr_codes.py <users.csv> <output_folder>")
        sys.exit(1)
    generate(sys.argv[1], sys.argv[2])
