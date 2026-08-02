# -*- coding: utf-8 -*-
import csv
from decimal import Decimal, ROUND_HALF_UP

rows = list(csv.DictReader(open(r"D:\Projects\music\_hejia_details.csv", encoding="utf-8-sig")))
sec_tot = {}
grand = Decimal("0")
for r in rows:
    qty = Decimal(r["工程数量"])
    price = Decimal(r["综合单价"])
    h = (qty * price).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    assert h == Decimal(r["合价"]), (r["序号"], h, r["合价"])
    sec = r["专业"]
    sec_tot[sec] = sec_tot.get(sec, Decimal("0")) + h
    grand += h
for k, v in sec_tot.items():
    print(k, v)
print("总计", grand)
print("行数", len(rows))
