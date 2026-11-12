"""Báo cáo chuyên cần có định dạng để nộp khoa: Excel (tổng hợp + chi tiết từng buổi) và PDF A4.

Dữ liệu vào là `ReportData` dựng sẵn ở router (đã kiểm tra quyền); hàm ở đây chỉ dàn trang.
"""
import io
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from fpdf import FPDF
from fpdf.fonts import FontFace
from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter

VN = ZoneInfo("Asia/Ho_Chi_Minh")
FONTS = Path(__file__).resolve().parent.parent / "fonts"
# Ký hiệu mỗi ô của bảng chi tiết buổi.
MARK = {"present": "C", "manual_present": "C", "excused": "P", "absent": "V", "rejected": "V", "suspicious": "?"}
LEGEND = "C: có mặt · P: vắng có phép · V: vắng · ?: chờ giảng viên duyệt"
SUMMARY_HEAD = ("STT", "MSSV", "Họ và tên", "Có mặt", "Có phép", "Vắng", "Chờ duyệt", "Số buổi", "Tỉ lệ có mặt",
                "Điểm CC", "Ghi chú")


@dataclass
class ReportData:
    school: str
    faculty: str
    cls: dict                 # code, name, semester, lecturer_name
    rows: list[dict]          # student_id, student_code, full_name, co_mat, vang_co_phep, vang, chua_duyet, so_buoi, warn
    sessions: list[dict]      # id, opened_at
    marks: dict[tuple[int, int], str]   # (student_id, session_id) -> status
    warn_absent: int
    now: datetime
    ban_pct: float = 20

    def rate(self, r: dict) -> float | None:
        return r["co_mat"] / r["so_buoi"] if r["so_buoi"] else None

    def note(self, r: dict) -> str:
        if r.get("cam_thi"):
            return f"Không đủ điều kiện dự thi (vắng {r['vang']} buổi)"
        return f"Cảnh báo: vắng {r['vang']} buổi" if r["warn"] else ""

    def flagged(self, r: dict) -> bool:
        return bool(r["warn"] or r.get("cam_thi"))

    @property
    def stamp(self) -> str:
        t = self.now.astimezone(VN)
        return f"Ngày {t.day:02d} tháng {t.month:02d} năm {t.year}"


def _day(dt: datetime) -> str:
    return dt.astimezone(VN).strftime("%d/%m")


# ---------------------------------------------------------------- Excel

THIN = Side(style="thin", color="94A3B8")
BOX = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)
HEAD_FILL = PatternFill("solid", fgColor="E0E7FF")
WARN_FILL = PatternFill("solid", fgColor="FFE4E6")
MARK_FILL = {"V": PatternFill("solid", fgColor="FFE4E6"), "P": PatternFill("solid", fgColor="F1F5F9"),
             "?": PatternFill("solid", fgColor="FEF3C7")}
CENTER = Alignment(horizontal="center", vertical="center", wrap_text=True)


def _title(ws, d: ReportData, last_col: int, title: str) -> int:
    """Khối tiêu đề (trường, khoa, tên báo cáo, thông tin lớp); trả số dòng bắt đầu bảng."""
    lines = [(d.school, Font(bold=True, size=12)), (d.faculty, Font(bold=True, size=12)), ("", None),
             (title, Font(bold=True, size=15)),
             (f"Lớp: {d.cls['code']} – {d.cls['name']}   ·   Học kỳ: {d.cls['semester']}", Font(size=11)),
             (f"Giảng viên: {d.cls['lecturer_name']}   ·   Số buổi đã điểm danh: {len(d.sessions)}", Font(size=11))]
    for i, (text, font) in enumerate(lines, start=1):
        ws.merge_cells(start_row=i, start_column=1, end_row=i, end_column=last_col)
        cell = ws.cell(i, 1, text)
        if font:
            cell.font = font
        cell.alignment = Alignment(horizontal="center" if i >= 4 else "left")
    return len(lines) + 2


def _header(ws, row: int, labels: list[str]) -> None:
    for col, text in enumerate(labels, start=1):
        c = ws.cell(row, col, text)
        c.font, c.fill, c.border, c.alignment = Font(bold=True), HEAD_FILL, BOX, CENTER
    ws.row_dimensions[row].height = 30


def _signature(ws, row: int, d: ReportData, col: int) -> None:
    ws.cell(row, col, d.stamp).alignment = Alignment(horizontal="center")
    ws.cell(row + 1, col, "Giảng viên").font = Font(bold=True)
    ws.cell(row + 1, col).alignment = Alignment(horizontal="center")
    ws.cell(row + 2, col, "(Ký, ghi rõ họ tên)").font = Font(italic=True, size=10)
    ws.cell(row + 2, col).alignment = Alignment(horizontal="center")
    ws.cell(row + 6, col, d.cls["lecturer_name"]).font = Font(bold=True)
    ws.cell(row + 6, col).alignment = Alignment(horizontal="center")


def to_xlsx(d: ReportData) -> bytes:
    wb = Workbook()
    ws = wb.active
    ws.title = "Tổng hợp"
    start = _title(ws, d, len(SUMMARY_HEAD), "BÁO CÁO CHUYÊN CẦN")
    _header(ws, start, list(SUMMARY_HEAD))
    for i, r in enumerate(d.rows, start=1):
        rate = d.rate(r)
        values = [i, r["student_code"], r["full_name"], r["co_mat"], r["vang_co_phep"], r["vang"], r["chua_duyet"],
                  r["so_buoi"], rate, r.get("diem"), d.note(r)]
        for col, v in enumerate(values, start=1):
            c = ws.cell(start + i, col, v)
            c.border = BOX
            c.alignment = Alignment(horizontal="left" if col in (3, 11) else "center", vertical="center", wrap_text=col == 11)
            if d.flagged(r):
                c.fill = WARN_FILL
        ws.cell(start + i, 10).number_format = "0.0"
        ws.cell(start + i, 9).number_format = "0%"
    end = start + len(d.rows)
    ws.cell(end + 2, 1, f"Ghi chú: sinh viên vắng từ {d.warn_absent} buổi trở lên được tô đỏ. "
                        "\"Có mặt\" gồm cả các buổi giảng viên duyệt tay. Điểm CC thang 10. "
                        f"Vắng không phép quá {d.ban_pct:g}% số buổi: không đủ điều kiện dự thi.").font = Font(italic=True, size=10)
    _signature(ws, end + 4, d, 9)
    for col, width in enumerate((6, 12, 30, 9, 9, 8, 10, 9, 12, 9, 30), start=1):
        ws.column_dimensions[get_column_letter(col)].width = width
    ws.freeze_panes = ws.cell(start + 1, 4)
    ws.page_setup.orientation = "portrait"
    ws.page_setup.paperSize = ws.PAPERSIZE_A4
    ws.page_setup.fitToWidth, ws.page_setup.fitToHeight = 1, 0
    ws.sheet_properties.pageSetUpPr.fitToPage = True
    ws.print_title_rows = f"{start}:{start}"

    det = wb.create_sheet("Chi tiết buổi")
    labels = ["STT", "MSSV", "Họ và tên"] + [f"B{i}\n{_day(s['opened_at'])}" for i, s in enumerate(d.sessions, start=1)] \
        + ["Có mặt", "Vắng"]
    start = _title(det, d, len(labels), "CHI TIẾT ĐIỂM DANH TỪNG BUỔI")
    _header(det, start, labels)
    for i, r in enumerate(d.rows, start=1):
        marks = [MARK.get(d.marks.get((r["student_id"], s["id"]), ""), "") for s in d.sessions]
        values = [i, r["student_code"], r["full_name"], *marks, r["co_mat"], r["vang"]]
        for col, v in enumerate(values, start=1):
            c = det.cell(start + i, col, v)
            c.border = BOX
            c.alignment = Alignment(horizontal="left" if col == 3 else "center")
            if v in MARK_FILL and 3 < col <= 3 + len(d.sessions):
                c.fill = MARK_FILL[v]
    det.cell(start + len(d.rows) + 2, 1, LEGEND).font = Font(italic=True, size=10)
    for col, width in enumerate([6, 12, 30] + [7] * len(d.sessions) + [8, 8], start=1):
        det.column_dimensions[get_column_letter(col)].width = width
    det.freeze_panes = det.cell(start + 1, 4)
    det.page_setup.orientation = "landscape"
    det.page_setup.paperSize = det.PAPERSIZE_A4
    det.page_setup.fitToWidth, det.page_setup.fitToHeight = 1, 0
    det.sheet_properties.pageSetUpPr.fitToPage = True

    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()


# ---------------------------------------------------------------- PDF

def to_pdf(d: ReportData) -> bytes:
    pdf = FPDF(orientation="P", unit="mm", format="A4")
    pdf.set_margins(15, 15, 15)
    pdf.set_auto_page_break(True, margin=15)
    pdf.add_font("Inter", "", str(FONTS / "Inter-Regular.ttf"))
    pdf.add_font("Inter", "B", str(FONTS / "Inter-Bold.ttf"))
    pdf.set_title(f"Báo cáo chuyên cần {d.cls['code']}")
    pdf.add_page()

    pdf.set_font("Inter", "B", 10)
    pdf.cell(0, 5, d.school, new_x="LMARGIN", new_y="NEXT")
    pdf.cell(0, 5, d.faculty, new_x="LMARGIN", new_y="NEXT")
    pdf.ln(5)
    pdf.set_font("Inter", "B", 15)
    pdf.cell(0, 8, "BÁO CÁO CHUYÊN CẦN", align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Inter", "", 10)
    pdf.cell(0, 6, f"Lớp: {d.cls['code']} – {d.cls['name']}   ·   Học kỳ: {d.cls['semester']}", align="C",
             new_x="LMARGIN", new_y="NEXT")
    pdf.cell(0, 6, f"Giảng viên: {d.cls['lecturer_name']}   ·   Số buổi đã điểm danh: {len(d.sessions)}", align="C",
             new_x="LMARGIN", new_y="NEXT")
    pdf.ln(4)

    widths = (8, 18, 42, 12, 12, 10, 13, 12, 12, 12, 29)  # tổng 180 mm
    head = FontFace(emphasis="BOLD", fill_color=(224, 231, 255))
    pdf.set_font("Inter", "", 8.5)
    with pdf.table(col_widths=widths, headings_style=head, line_height=5.5, text_align=(
            "CENTER", "CENTER", "LEFT", "CENTER", "CENTER", "CENTER", "CENTER", "CENTER", "CENTER", "CENTER", "LEFT"),
            borders_layout="ALL", repeat_headings=1) as table:
        table.row(["STT", "MSSV", "Họ và tên", "Có mặt", "Có phép", "Vắng", "Chờ duyệt", "Số buổi", "Tỉ lệ", "Điểm CC",
                   "Ghi chú"])
        for i, r in enumerate(d.rows, start=1):
            rate = d.rate(r)
            style = FontFace(fill_color=(255, 228, 230)) if d.flagged(r) else None
            table.row([str(i), r["student_code"] or "", r["full_name"], str(r["co_mat"]), str(r["vang_co_phep"]),
                       str(r["vang"]), str(r["chua_duyet"]), str(r["so_buoi"]),
                       "–" if rate is None else f"{round(rate * 100)}%",
                       "–" if r.get("diem") is None else f"{r['diem']:.1f}".replace(".", ","), d.note(r)], style=style)

    pdf.ln(3)
    pdf.set_font("Inter", "", 8)
    pdf.multi_cell(0, 4.5, f"Ghi chú: sinh viên vắng từ {d.warn_absent} buổi trở lên được tô đỏ. \"Có mặt\" gồm cả các "
                           f"buổi giảng viên duyệt tay. Điểm CC thang 10. Vắng không phép quá {d.ban_pct:g}% số buổi: "
                           "không đủ điều kiện dự thi. Chi tiết từng buổi xem trong file Excel.")
    if pdf.get_y() > 230:
        pdf.add_page()
    pdf.ln(6)
    x = 110
    for text, style, h in ((d.stamp, "", 6), ("Giảng viên", "B", 6), ("(Ký, ghi rõ họ tên)", "", 5)):
        pdf.set_x(x)
        pdf.set_font("Inter", style, 10 if style else 9)
        pdf.cell(85, h, text, align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(18)
    pdf.set_x(x)
    pdf.set_font("Inter", "B", 10)
    pdf.cell(85, 6, d.cls["lecturer_name"], align="C")
    return bytes(pdf.output())


# ---------------------------------------------------------------- Danh sách cấm thi

@dataclass
class BannedData:
    school: str
    faculty: str
    semester: str
    ban_pct: float
    rows: list[dict]   # class_code, class_name, lecturer_name, student_code, full_name, vang, so_buoi, pct
    now: datetime

    @property
    def stamp(self) -> str:
        t = self.now.astimezone(VN)
        return f"Ngày {t.day:02d} tháng {t.month:02d} năm {t.year}"


BANNED_HEAD = ("STT", "Mã lớp", "Tên lớp", "MSSV", "Họ và tên", "Số buổi", "Vắng không phép", "Tỉ lệ vắng")
BANNED_TITLE = "DANH SÁCH SINH VIÊN KHÔNG ĐỦ ĐIỀU KIỆN DỰ THI"


def banned_xlsx(d: BannedData) -> bytes:
    wb = Workbook()
    ws = wb.active
    ws.title = "Cấm thi"
    lines = [(d.school, Font(bold=True, size=12)), (d.faculty, Font(bold=True, size=12)), ("", None),
             (BANNED_TITLE, Font(bold=True, size=14)),
             (f"Học kỳ: {d.semester}   ·   Tiêu chí: vắng không phép quá {d.ban_pct:g}% số buổi", Font(size=11))]
    for i, (text, font) in enumerate(lines, start=1):
        ws.merge_cells(start_row=i, start_column=1, end_row=i, end_column=len(BANNED_HEAD))
        cell = ws.cell(i, 1, text)
        if font:
            cell.font = font
        cell.alignment = Alignment(horizontal="center" if i >= 4 else "left")
    start = len(lines) + 2
    _header(ws, start, list(BANNED_HEAD))
    for i, r in enumerate(d.rows, start=1):
        values = [i, r["class_code"], r["class_name"], r["student_code"], r["full_name"], r["so_buoi"], r["vang"],
                  r["pct"] / 100]
        for col, v in enumerate(values, start=1):
            c = ws.cell(start + i, col, v)
            c.border = BOX
            c.alignment = Alignment(horizontal="left" if col in (3, 5) else "center")
        ws.cell(start + i, 8).number_format = "0%"
    if not d.rows:
        ws.cell(start + 1, 1, "Không có sinh viên nào.").font = Font(italic=True)
    end = start + max(len(d.rows), 1)
    for k, (text, font) in enumerate(((d.stamp, None), ("Trưởng khoa", Font(bold=True)),
                                      ("(Ký, ghi rõ họ tên)", Font(italic=True, size=10)))):
        c = ws.cell(end + 3 + k, 6, text)
        c.alignment = Alignment(horizontal="center")
        if font:
            c.font = font
    for col, width in enumerate((6, 11, 28, 12, 28, 9, 14, 11), start=1):
        ws.column_dimensions[get_column_letter(col)].width = width
    ws.page_setup.paperSize = ws.PAPERSIZE_A4
    ws.page_setup.fitToWidth, ws.page_setup.fitToHeight = 1, 0
    ws.sheet_properties.pageSetUpPr.fitToPage = True
    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()


def banned_pdf(d: BannedData) -> bytes:
    pdf = FPDF(orientation="P", unit="mm", format="A4")
    pdf.set_margins(15, 15, 15)
    pdf.set_auto_page_break(True, margin=15)
    pdf.add_font("Inter", "", str(FONTS / "Inter-Regular.ttf"))
    pdf.add_font("Inter", "B", str(FONTS / "Inter-Bold.ttf"))
    pdf.set_title(f"Danh sách cấm thi {d.semester}")
    pdf.add_page()
    pdf.set_font("Inter", "B", 10)
    pdf.cell(0, 5, d.school, new_x="LMARGIN", new_y="NEXT")
    pdf.cell(0, 5, d.faculty, new_x="LMARGIN", new_y="NEXT")
    pdf.ln(5)
    pdf.set_font("Inter", "B", 13)
    pdf.cell(0, 8, BANNED_TITLE, align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Inter", "", 10)
    pdf.cell(0, 6, f"Học kỳ: {d.semester}   ·   Tiêu chí: vắng không phép quá {d.ban_pct:g}% số buổi", align="C",
             new_x="LMARGIN", new_y="NEXT")
    pdf.ln(4)
    pdf.set_font("Inter", "", 8.5)
    if d.rows:
        with pdf.table(col_widths=(9, 18, 38, 18, 42, 15, 22, 18), line_height=5.5,
                       headings_style=FontFace(emphasis="BOLD", fill_color=(224, 231, 255)),
                       text_align=("CENTER", "CENTER", "LEFT", "CENTER", "LEFT", "CENTER", "CENTER", "CENTER"),
                       repeat_headings=1) as table:
            table.row(list(BANNED_HEAD))
            for i, r in enumerate(d.rows, start=1):
                table.row([str(i), r["class_code"], r["class_name"], r["student_code"] or "", r["full_name"],
                           str(r["so_buoi"]), str(r["vang"]), f"{r['pct']}%"])
    else:
        pdf.cell(0, 8, "Không có sinh viên nào.", align="C", new_x="LMARGIN", new_y="NEXT")
    if pdf.get_y() > 230:
        pdf.add_page()
    pdf.ln(10)
    for text, style in ((d.stamp, ""), ("Trưởng khoa", "B"), ("(Ký, ghi rõ họ tên)", "")):
        pdf.set_x(110)
        pdf.set_font("Inter", style, 10 if style else 9)
        pdf.cell(85, 6, text, align="C", new_x="LMARGIN", new_y="NEXT")
    return bytes(pdf.output())
