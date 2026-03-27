# Hướng Dẫn Chuyển Đổi File AutoCAD (DXF) Sang GeoJSON Cho EarthRanger

> **Tài liệu tham khảo:** [Configure and Import Map Features in EarthRanger Admin](https://support.earthranger.com/step-8-admin-setup/map-features-configuration)

---

## Mục Lục

1. [Yêu Cầu Của EarthRanger](#1-yêu-cầu-của-earthranger)
2. [Công Cụ Cần Thiết](#2-công-cụ-cần-thiết)
3. [Bước 1: Chuẩn Bị File DXF](#bước-1-chuẩn-bị-file-dxf)
4. [Bước 2: Import File DXF Vào QGIS](#bước-2-import-file-dxf-vào-qgis)
5. [Bước 3: Chuyển Đường Thành Vùng (Lines to Polygons)](#bước-3-chuyển-đường-thành-vùng-lines-to-polygons)
6. [Bước 4: Sửa Lỗi Hình Học (Fix Geometries)](#bước-4-sửa-lỗi-hình-học-fix-geometries)
7. [Bước 5: Gộp Các Vùng (Dissolve)](#bước-5-gộp-các-vùng-dissolve)
8. [Bước 6: Đơn Giản Hóa Hình Học (Simplify)](#bước-6-đơn-giản-hóa-hình-học-simplify)
9. [Bước 7: Thêm Thuộc Tính Tên (Name)](#bước-7-thêm-thuộc-tính-tên-name)
10. [Bước 8: Xuất File GeoJSON](#bước-8-xuất-file-geojson)
11. [Bước 9: Import Vào EarthRanger](#bước-9-import-vào-earthranger)
12. [Ghi Chú Quan Trọng](#ghi-chú-quan-trọng)

---

## 1. Yêu Cầu Của EarthRanger

EarthRanger hỗ trợ hai loại file không gian địa lý: **Shapefile** (`.shp`) và **GeoJSON** (`.geojson`).

### Yêu cầu bắt buộc cho file GeoJSON:

| Yêu cầu | Chi tiết |
|----------|----------|
| **Định dạng** | GeoJSON (`.geojson`) |
| **Hệ tọa độ** | Phải sử dụng **EPSG:4326** (WGS 84) |
| **Số lớp (Layer)** | Mỗi file chỉ chứa **1 layer** duy nhất |
| **Loại đối tượng** | Mỗi file chỉ chứa **1 loại** đối tượng (polygon HOẶC line HOẶC point) |
| **Thuộc tính tên** | Mỗi đối tượng phải có thuộc tính **tên duy nhất** (không được NULL) |
| **Kích thước file** | Càng nhỏ càng tốt — đơn giản hóa hình học nếu cần |

### Tối ưu hiệu suất:

- **Đơn giản hóa hình học**: Sử dụng công cụ Simplify trong QGIS để giảm số lượng đỉnh (vertex)
- **Xóa thuộc tính không cần thiết**: Loại bỏ các cột thuộc tính không dùng trong EarthRanger
- **Nhóm hợp lý**: Chỉ đưa các đối tượng cùng Feature Class vào một file

### Cấu trúc phân cấp trong EarthRanger:

```
Display Category (VD: Boundaries)
  └── Feature Class (VD: Administrative District)
        └── Features (VD: Buon Ja Wam, Xã Ea Kiết)
```

---

## 2. Công Cụ Cần Thiết

| Công cụ | Mục đích |
|---------|----------|
| **QGIS** (miễn phí) | Xử lý toàn bộ quy trình chuyển đổi |
| **ODA File Converter** (miễn phí, tùy chọn) | Chuyển đổi DWG sang DXF nếu cần |

> **Lưu ý:** QGIS không hỗ trợ tốt file `.dwg`. Hãy chuyển sang `.dxf` trước khi import.
> Nếu bạn có file DWG, dùng [ODA File Converter](https://www.opendesign.com/guestfiles/oda_file_converter) hoặc nhờ người tạo file AutoCAD xuất ra DXF.

---

## Bước 1: Chuẩn Bị File DXF

Nếu file gốc là `.dwg`, cần chuyển sang `.dxf`:

- Mở file trong AutoCAD → **Save As** → chọn định dạng DXF
- Hoặc sử dụng **ODA File Converter** (miễn phí): https://www.opendesign.com/guestfiles/oda_file_converter
- Hoặc sử dụng **LibreCAD** (miễn phí, mã nguồn mở)

---

## Bước 2: Import File DXF Vào QGIS

### 2.1. Mở hộp thoại Import

1. Mở QGIS
2. Vào **Layer → Add Layer → Add Vector Layer**
3. Chọn **Source type**: File
4. Nhấn **...** (Browse) → Chọn file `.dxf` của bạn

### 2.2. Cài đặt Import (Options)

| Tùy chọn | Giá trị | Ghi chú |
|-----------|---------|---------|
| **CLOSED_LINE_AS_POLYGON** | **Yes** | Chuyển polyline khép kín thành polygon — **quan trọng cho ranh giới!** |
| **INLINE_BLOCKS** | **Yes** | Mở rộng block references thành hình học thực |
| **MERGE_BLOCK_GEOMETRIES** | Default | Giữ mặc định |
| **TRANSLATE_ESCAPE_SEQUENCES** | Default | Giữ mặc định |
| **INCLUDE_RAW_CODE_VALUES** | Default | Giữ mặc định |
| **3D_EXTENSIBLE_MODE** | Default | Giữ mặc định |
| **HATCH_TOLERANCE** | Default | Giữ mặc định |
| **ENCODING** | **UTF-8** | Chọn UTF-8 nếu có tên tiếng Việt trong layer |

### 2.3. Chọn Sublayer

Sau khi nhấn **Add**, QGIS hiển thị danh sách sublayers:

- Chọn **MultiLineString** (chứa các đường ranh giới)
- Bỏ chọn **PointZ** (chỉ là các điểm vertex, không cần thiết)
- Nhấn **Add Layers**

### 2.4. Thiết lập hệ tọa độ VN2000

1. Chuột phải lên layer vừa import → **Layer CRS → Set Layer CRS...**
2. Tìm kiếm hệ tọa độ VN2000 phù hợp với khu vực:
   - `EPSG:3405` — VN-2000 / UTM zone 48N
   - `EPSG:3406` — VN-2000 / UTM zone 49N
   - `EPSG:9218` — VN-2000 / TM-3 108-30 (khu vực miền Trung)
   - Hoặc tìm "VN2000" để chọn zone phù hợp
3. Nhấn **OK**

> **Mẹo:** Kiểm tra ô bản đồ đỏ (preview) trùng với khu vực nghiên cứu của bạn.

---

## Bước 3: Chuyển Đường Thành Vùng (Lines to Polygons)

File DXF thường lưu ranh giới dạng đường (line), cần chuyển thành vùng (polygon).

### 3.1. Mở công cụ

1. Vào **Processing → Toolbox**
2. Tìm kiếm **"Lines to polygons"**

### 3.2. Cài đặt

| Tùy chọn | Giá trị |
|-----------|---------|
| **Input layer** | Layer DXF vừa import (MultiLineString) |
| **Polygons** | [Create temporary layer] |
| **Open output file after running** | ✅ Đánh dấu |

### 3.3. Nhấn **Run**

Kết quả: Layer mới **"Polygons"** xuất hiện với các vùng ranh giới có màu tô.

### 3.4. Kiểm tra Attribute Table

1. Chuột phải lên layer **Polygons** → **Open Attribute Table**
2. Xem cột **Layer** — chứa tên các layer AutoCAD gốc
3. Ghi nhận số lượng đối tượng và các giá trị trong cột Layer

---

## Bước 4: Sửa Lỗi Hình Học (Fix Geometries)

Bước này cần thiết để tránh lỗi khi thực hiện các bước tiếp theo (Dissolve, Simplify).

### 4.1. Mở công cụ

1. Vào **Processing → Toolbox**
2. Tìm kiếm **"Fix geometries"**

### 4.2. Cài đặt

| Tùy chọn | Giá trị |
|-----------|---------|
| **Input layer** | Polygons [EPSG:xxxx] |
| **Repair method** | **Linework** |
| **Fixed geometries** | [Create temporary layer] |
| **Open output file after running** | ✅ Đánh dấu |

### 4.3. Nhấn **Run**

Kết quả: Layer mới **"Fixed geometries"** xuất hiện với hình học đã được sửa.

---

## Bước 5: Gộp Các Vùng (Dissolve)

Nếu cần gộp nhiều polygon thành 1 polygon duy nhất (VD: gộp tất cả ranh giới thành 1 vùng).

### 5.1. Mở công cụ

1. Vào **Processing → Toolbox**
2. Tìm kiếm **"Dissolve"**

### 5.2. Cài đặt

| Tùy chọn | Giá trị | Ghi chú |
|-----------|---------|---------|
| **Input layer** | Fixed geometries [EPSG:xxxx] | Dùng layer đã fix, KHÔNG dùng layer gốc |
| **Dissolve field(s)** | **Không chọn field nào** (0 fields selected) | Gộp TẤT CẢ thành 1 polygon |
| **Keep disjoint features separate** | ☐ Bỏ đánh dấu | |
| **Dissolved** | [Create temporary layer] | |

> **Lưu ý:** Nếu muốn gộp theo nhóm (VD: tách riêng "ranh" và "RANH CŨ"), chọn cột **Layer** trong Dissolve field.

### 5.3. Nhấn **Run**

Kết quả: Layer mới **"Dissolved"** với 1 polygon duy nhất.

---

## Bước 6: Đơn Giản Hóa Hình Học (Simplify)

Giảm số lượng đỉnh để file nhỏ hơn, tải nhanh hơn trong EarthRanger.

### 6.1. Mở công cụ

1. Vào **Vector → Geometry Tools → Simplify**
2. Hoặc tìm **"Simplify"** trong Processing Toolbox

### 6.2. Cài đặt

| Tùy chọn | Giá trị | Ghi chú |
|-----------|---------|---------|
| **Input layer** | Dissolved | |
| **Simplification method** | **Distance (Douglas-Peucker)** | Phương pháp phổ biến nhất cho ranh giới |
| **Tolerance** | **50** (mét) | Phù hợp cho ranh giới khu bảo tồn |
| **Simplified** | [Create temporary layer] | |

### Bảng tham khảo Tolerance:

| Tolerance | Hiệu quả | Phù hợp cho |
|-----------|-----------|-------------|
| 10-20m | Ít đơn giản, giữ chi tiết | Khu vực nhỏ, cần ranh giới chính xác |
| **50m** | **Cân bằng tốt** | **Hầu hết ranh giới khu bảo tồn** |
| 100m+ | Đơn giản mạnh, ít chi tiết | Khu vực rất lớn, bản đồ tổng quan |

### 6.3. Nhấn **Run**

### 6.4. Kiểm tra kết quả

- So sánh layer **Simplified** với layer gốc
- Phóng to (zoom in) để kiểm tra hình dạng
- Nếu quá gồ ghề → giảm tolerance (VD: 30)
- Nếu vẫn quá chi tiết → tăng tolerance (VD: 75)

---

## Bước 7: Thêm Thuộc Tính Tên (Name)

EarthRanger **yêu cầu bắt buộc** mỗi đối tượng phải có tên duy nhất.

### 7.1. Mở Attribute Table

1. Chuột phải lên layer **Simplified** → **Open Attribute Table**

### 7.2. Thêm cột Name

1. Nhấn biểu tượng **bút chì** ✏️ (Toggle Editing)
2. Nhấn nút **New Field** (hoặc **Ctrl+W**)
3. Cài đặt:
   - **Name**: `Name`
   - **Type**: Text (string)
   - **Length**: 100
4. Nhấn **OK**

### 7.3. Nhập tên

1. Nhấn đúp (double-click) vào ô trống trong cột **Name**
2. Gõ tên cho đối tượng (VD: `Buon Ja Wam`)
3. Nhấn **Enter**

### 7.4. Lưu thay đổi

1. Nhấn **Save Edits** 💾 (hoặc **Ctrl+S**)
2. Nhấn biểu tượng **bút chì** ✏️ để thoát chế độ chỉnh sửa

### 7.5. Xóa các cột không cần thiết (Tùy chọn)

Để giảm kích thước file, xóa các cột không dùng:

- ❌ PaperSpace — Xóa
- ❌ SubClasses — Xóa
- ❌ Linetype — Xóa
- ❌ EntityHandle — Xóa
- ❌ Text — Xóa
- ❌ Layer — Xóa
- ✅ **Name** — **GIỮ LẠI**

**Cách xóa cột:**
1. Trong chế độ Edit (bút chì đã bật)
2. Nhấn nút **Delete Field** trong Attribute Table toolbar
3. Chọn các cột cần xóa
4. Nhấn **OK** → **Save Edits**

---

## Bước 8: Xuất File GeoJSON

### 8.1. Mở hộp thoại Export

1. Chuột phải lên layer **Simplified** → **Export → Save Features As...**

### 8.2. Cài đặt xuất file

| Tùy chọn | Giá trị | Ghi chú |
|-----------|---------|---------|
| **Format** | **GeoJSON** | |
| **File name** | Nhấn **...** → Chọn vị trí → Đặt tên (VD: `Buon_Ja_Wam.geojson`) | |
| **CRS** | **EPSG:4326 - WGS 84** | ⚠️ **BẮT BUỘC!** Không dùng VN-2000 |
| **Encoding** | UTF-8 | |

> **Lưu ý quan trọng:**
> - **CRS (EPSG:4326)** = Hệ tọa độ WGS 84 sử dụng latitude/longitude — đây là yêu cầu của EarthRanger
> - **KHÔNG chọn** Project CRS hoặc Layer CRS (đây là VN-2000, không tương thích với EarthRanger)

### 8.3. Layer Options

| Tùy chọn | Giá trị | Ghi chú |
|-----------|---------|---------|
| **COORDINATE_PRECISION** | **6** | 6 chữ số thập phân ≈ 10cm, đủ cho ranh giới |
| **RFC7946** | NO | |
| **WRITE_BBOX** | NO | |

### Bảng tham khảo Coordinate Precision:

| Giá trị | Độ chính xác | Ghi chú |
|---------|-------------|---------|
| 15 | Dưới millimet | Quá mức, file lớn |
| 8 | ~1 millimet | Tốt cho công việc chi tiết |
| **6** | **~10 centimet** | **Khuyến nghị cho EarthRanger** |

### 8.4. Geometry

| Tùy chọn | Giá trị |
|-----------|---------|
| **Geometry type** | **Automatic** |

### 8.5. Chọn cột xuất (Select fields to export)

Mở rộng phần này và chỉ đánh dấu:
- ✅ **Name** — Giữ lại
- ❌ Tất cả cột khác — Bỏ đánh dấu

### 8.6. Nhấn **OK**

File GeoJSON đã sẵn sàng!

---

## Bước 9: Import Vào EarthRanger

### 9.1. Truy cập trang Import

1. Đăng nhập **EarthRanger Admin**
2. Vào **Map Layers → Feature Import Files**
3. Nhấn **Add Feature Import File**

### 9.2. Cài đặt Import

| Tùy chọn | Giá trị |
|-----------|---------|
| **File type** | GeoJSON |
| **SpatialFile Name** | Tên dễ nhận biết (VD: `Buon Ja Wam`) |
| **Description** | Mô tả (tùy chọn) |
| **Data** | Chọn file `.geojson` vừa xuất |
| **Feature type** | Chọn Feature Class phù hợp (VD: Administrative District) |
| **Name field** | Gõ: `Name` |
| **Id field** | (Tùy chọn) Để trống hoặc gõ `Name` |

### 9.3. Nhấn **Save**

### 9.4. Xác minh kết quả

1. Vào trang chính EarthRanger
2. Nhấn tab **Map Layers**
3. Chọn **Features** để xem dữ liệu đã import
4. Làm mới trình duyệt (F5) nếu cần

---

## Ghi Chú Quan Trọng

### File DWG vs DXF
- QGIS **không hỗ trợ tốt** file `.dwg`
- Luôn chuyển sang `.dxf` trước khi làm việc với QGIS

### Tách Layer (Nếu Cần)
Nếu file DXF có nhiều loại ranh giới cần tách riêng:
1. Vào **Processing → Toolbox**
2. Tìm **"Split vector layer by attribute value"**
3. Chọn cột **Layer** (tên AutoCAD layer) để tách
4. Xuất mỗi layer thành 1 file GeoJSON riêng

### Cấu trúc phân cấp EarthRanger
EarthRanger không hỗ trợ lồng feature trong feature. Cấu trúc:
```
Display Category (VD: Boundaries)
  ├── Feature Class (VD: Districts)
  │     └── Xã Ea Kiết
  └── Feature Class (VD: Villages)
        └── Buon Ja Wam
```

### Quy trình tóm tắt

```
File DWG → Chuyển sang DXF → Import QGIS → Lines to Polygons
→ Fix Geometries → Dissolve → Simplify → Thêm Name
→ Export GeoJSON (EPSG:4326) → Import EarthRanger
```

---

> **Tài liệu tham khảo:** https://support.earthranger.com/step-8-admin-setup/map-features-configuration
