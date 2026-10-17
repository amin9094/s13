# SENTINEL 9 — اصلاح خطای Build / Quality Gate در Railway

## مشکل مشاهده‌شده
پس از رفع مشکل نصب پکیج‌های Debian، تست `tests/test_v844_release_and_journal.py::test_direct_source_dockerfile_has_all_copy_inputs_and_no_bootstrap_dependency` شکست می‌خورد.
اسکریپت `scripts/build_lean_railway_release.py` از Dockerfile انتظار داشت Stage قدیمی `FROM python:3.12-slim-bookworm AS runtime` را ببیند، اما Dockerfile فعلی برای جلوگیری از نصب تکراری Debian از `FROM system-dependencies AS runtime` استفاده می‌کند.

## اصلاح
- اسکریپت بسته‌ساز lean هر دو قالب قدیمی و جدید Dockerfile را می‌پذیرد.
- در قالب جدید، Stage مشترک نصب سیستم‌عامل حفظ و Stage مخصوص quality حذف می‌شود؛ خروجی lean مستقلاً قابل ساخت است.
- دستورهای `COPY --from=quality` به کپی مستقیم از سورس تبدیل می‌شوند و وابستگی به فایل `.quality-stage-passed` حذف می‌شود.
- کنترل صریح اضافه شده تا تغییر ناخواسته Dockerfile به خروجی ناقص منجر نشود.
- تست رگرسیون تقویت شد تا وجود Stage مشترک و حذف Stage کیفیت را بررسی کند.
- فایل `sentinel_runtime.zip` و امضای SHA-256 دوباره از سورس اصلاح‌شده ساخته شدند.

## وضعیت تست‌ها
- تست مشکل‌دار روی سورس قبل از اصلاح شکست و پس از اصلاح موفق شد.
- مجموعه تست‌های مرتبط با بسته‌سازی و بازیابی Runtime (به‌جز تست غیرمرتبطی که کتابخانه Redis در این محیط نداشت) با موفقیت اجرا شدند.
- آزمون کامل Docker / Railway و تأیید تولیدی هنوز در این محیط اجرا نشده؛ Railway باید پس از آپلود این ZIP بیلد تازه انجام دهد.

## نحوه انتشار
1. **فقط محتوای این ZIP** را در ریشه سورس مخزن آپلود یا جایگزین کنید. فایل‌های نسخه‌های قبلی را مخلوط نکنید.
2. در Railway مطمئن شوید Dockerfile اصلی (`Dockerfile`) انتخاب شده، نه `Dockerfile.quality`.
3. از آخرین commit، Deploy جدید اجرا کنید و در صورت استفاده از کش قدیمی، Clear Build Cache را امتحان کنید.
4. اگر شکست دیگری رخ داد، بخش پایین Build Logs شامل نام تست و traceback را ارسال کنید.

این اصلاح منطق سیگنال، تنظیمات دیتابیس، کلیدها یا توکن‌ها را تغییر نمی‌دهد.
