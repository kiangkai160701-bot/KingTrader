# KingStock POS + Multi-tenant SaaS — Implementation Plan

สถานะเอกสาร: ออกแบบ / ยังไม่ deploy

## เป้าหมาย
พัฒนา KingStock เป็น POS สำหรับร้านค้าปลีกที่ให้ลูกค้าเช่าระบบ โดยหน้าแรกหลังล็อกอินเป็นหน้าขายสินค้า และยังคงเมนูสต๊อกเดิม ประวัติ ผู้ใช้ และตั้งค่าไว้

## ข้อตกลงที่ยืนยันแล้ว
- ช่องทางชำระเงิน: เงินสด, โอนเงิน / QR
- แยกข้อมูลผู้เช่า (tenant) ให้เด็ดขาด
- รักษาข้อมูลเดิมใน `private.inventory_state` และ flow `api_get_state` / `api_sync`
- ห้ามแก้โปรเจกต์อื่น: scope เฉพาะ `kiangkai160701-bot/Kingstock`
- POS checkout ต้องเป็น DB transaction/RPC ฝั่ง server เท่านั้น

## สภาพระบบจากการตรวจล่าสุด
- GitHub repo: https://github.com/kiangkai160701-bot/Kingstock
- ฐานข้อมูล Supabase: `vizffwfyccpyqesjjjaf`
- ระบบเดิมเก็บ state ใน JSONB ที่ `private.inventory_state.data` โดยมี sections products/users/log/categories/units/roles
- ตารางเดิม `private.inventory_branches`, `private.inventory_sessions`, `private.inventory_state`, `private.inventory_state_backups`, `private.inventory_global_admin`
- ฟังก์ชันเดิม `api_get_state` และ `api_sync` ใช้ custom token hash และ branch_id; เป็น SECURITY DEFINER
- snapshot ณ เวลาตรวจ: มี branch เดิม 1 แห่ง, products 0 รายการ, users 1 รายการ, log 0 รายการ, state version 7 (ตัวเลขนี้เป็น snapshot ไม่ใช่ข้อสรุปว่าข้อมูล production จะว่างตลอดไป)
- โค้ดเดิมยังมี logic ที่ลบ `price` และ `cost` จาก product object ในเส้นทาง migration/local data จึงไม่ควรยัดราคาขาย POS ลงใน stock JSONB โดยไม่ตรวจทุกจุด

## ความเสี่ยงด้านความปลอดภัยที่พบ
Supabase Advisor แจ้ง CRITICAL: RLS ปิดอยู่บน `private.inventory_branches` และ `private.inventory_state_backups`. ห้ามเปิด RLS แบบไม่มี policies เพราะอาจทำให้ flow เดิมหยุดทำงาน; ต้องตรวจ privileges, policies และ RPC access path ก่อนแก้

ระบบเดิมยังใช้ session token แบบ custom ไม่ใช่ `auth.uid()` จึงห้ามสร้าง RLS policy แบบ `auth.uid() = tenant_id` แล้วคิดว่าจะป้องกัน tenant ได้โดยอัตโนมัติ. ต้องให้ RPC ที่ตรวจ token hash, expiry, tenant_id, branch_id, active status และ permission เป็นผู้กำหนดสิทธิ์อย่างชัดเจน. SECURITY DEFINER ต้องกำหนด search_path ว่าง, qualify object names, ตรวจ token ทุกครั้ง, จำกัด EXECUTE grants และไม่ส่ง service-role key ไป browser

## แบบจำลองข้อมูล POS ที่เสนอ
สร้าง schema/table ใหม่แยกจาก JSONB เดิม:
- `private.inventory_tenants`: tenant_id, name, status, plan, subscription dates
- `private.pos_products`: tenant_id, branch_id, sku/barcode, name, category, sale_price, stock_qty, active
- `private.pos_sales`: tenant_id, branch_id, receipt_no, cashier, payment_method (cash|qr), subtotal, discount, total, idempotency_key, created_at
- `private.pos_sale_items`: tenant_id, sale_id, product_id, product_name_snapshot, sku_snapshot, unit_price_snapshot, qty, line_total

ทุกตารางต้องมี tenant_id และ composite foreign keys ที่ยืนยัน tenant เดียวกัน. Unique idempotency key ต่อ tenant/branch ป้องกันการกดรับชำระซ้ำ. เก็บราคา/ชื่อสินค้า ณ เวลาขายเป็น snapshot เพื่อให้แก้ราคาภายหลังไม่เปลี่ยนบิลเก่า.

## Checkout contract
RPC `api_pos_checkout(p_token, p_idempotency_key, p_items, p_payment_method)`:
1. ตรวจ token hash + expires_at และ resolve session -> branch -> tenant -> cashier
2. อนุญาตเฉพาะ payment_method = cash หรือ qr
3. lock แถวสินค้าใน tenant/branch ด้วย SELECT ... FOR UPDATE
4. validate สินค้าทุกตัว, ราคา, จำนวน, สต๊อกเพียงพอ; ห้ามเชื่อราคา/ยอดรวมจาก browser
5. คำนวณ subtotal/discount/total ใน DB
6. insert sale + sale items snapshots + decrement stock ใน transaction เดียว
7. idempotency conflict คืนบิลเดิม ไม่ตัดสต๊อกซ้ำ
8. บันทึก cashier, branch, tenant, timestamp และ payment method
9. return receipt + totals + remaining stock

## แผนดำเนินงานเป็นระยะ
1. UX prototype: หน้า POS, ค้นหา/หมวดหมู่, cart, เลือกเงินสดหรือ QR — ข้อมูลสมมติ ไม่เชื่อม DB
2. Auth/tenant design: ออกแบบ mapping ผู้เช่า/สาขา/สมาชิกกับ custom session; ปิดช่องทาง enumerate branch ข้าม tenant
3. Additive DB migration ใน development branch ก่อน: สร้าง tenant + POS tables + constraints + RPCs; ไม่แก้ JSONB เดิมและไม่ migrate/drop ข้อมูล
4. Tests: cross-tenant read/write, inactive tenant, expired token, wrong branch, insufficient stock, concurrent checkout, duplicate idempotency, price tampering
5. Integrate UI with RPC; default tab POS หลัง login; stock/history/settings ยังคงอยู่
6. backup + staged production migration + verify counts and rollback plan ก่อน deploy

## เกณฑ์ยอมรับก่อนเปิดร้านจริง
- tenant A ไม่สามารถอ่าน/แก้ไขสินค้า บิล หรือสต๊อกของ tenant B
- ทุกบิลมี cashier/branch/tenant/payment_method/timestamp และรายการสินค้า snapshot
- การรับชำระซ้ำไม่ตัด stock ซ้ำ
- สต๊อกไม่ติดลบแม้มีหลายเครื่องขายพร้อมกัน
- การล้มเหลวระหว่าง checkout ต้อง rollback ทั้งบิลและสต๊อก
- flow login, api_get_state, api_sync, branch management เดิมผ่าน regression tests
- มี backup และตรวจจำนวนข้อมูลก่อน/หลัง migration

## สถานะงาน
- [x] ตรวจ repo, โครงสร้าง Supabase และ RPC เดิม
- [x] สร้าง branch `feature/pos-multitenant` สำหรับงานพัฒนา
- [x] สร้าง UX prototype แบบ standalone (mock data)
- [ ] ออกแบบ/ทดสอบ tenant auth และ RPC checkout
- [ ] สร้าง migration ใน development DB branch
- [ ] เชื่อม UI กับฐานข้อมูลจริง
- [ ] regression/security tests
- [ ] production rollout

## ข้อห้ามสำหรับผู้พัฒนาคนถัดไป
- ห้ามล้างหรือเขียนทับ `private.inventory_state.data`
- ห้ามแก้ `api_sync` / `api_get_state` จนกว่าจะมี regression tests
- ห้ามเปิด RLS บนตารางเดิมแบบไม่มี policy
- ห้ามใช้ client-supplied price/total เป็นยอดขายจริง
- ห้าม deploy prototype/mock data เป็น production
- ห้ามเปลี่ยนหรือแตะ repository/ฐานข้อมูลของโปรเจกต์อื่น
