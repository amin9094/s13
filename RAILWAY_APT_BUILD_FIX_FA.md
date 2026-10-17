# SENTINEL 9.0.0-candidate.36 — رفع مشکلات Build مربوط به APT و بستهٔ Runtime

## تغییرات
- در `Dockerfile` نصب پکیج‌های Debian به یک مرحلهٔ مشترک `system-dependencies` منتقل شد؛ دو مرحلهٔ `quality` و `runtime` از همان لایه استفاده می‌کنند و درخواست جداگانهٔ `apt-get` از مرحلهٔ runtime حذف شده است.
- نصب پکیج‌ها دارای retry و fallback محدود بین مخزن پیش‌فرض، HTTPS و mirror جایگزین است؛ در صورت شکست نهایی خطای مشخص صادر می‌شود.
- `Dockerfile.quality` برای ساخت مستقل quality نیز دارای مکانیزم retry/mirror است.
- ابزارهای موردنیاز برنامه (`nodejs`، فونت‌ها، `gosu`، `postgresql-client` و سایر بسته‌های قبلی) حفظ شده‌اند.
- به آزمون‌های مربوط به ساخت Docker و بستهٔ Runtime کنترل عدم تکرار APT اضافه شد.
- فایل‌های غایب در checkpoint یعنی `sentinel_runtime.zip` و `sentinel_runtime.zip.sha256` بر اساس سورس فعلی ساخته و بررسی شدند.

## آزمون‌های انجام‌شده در محیط آماده‌سازی
- 16 آزمون مربوط به ساخت بسته و restore/runtime: موفق
- بررسی syntax دستورات Shell فایل‌های Dockerfile: موفق
- بررسی syntax جاوااسکریپت Mini App: موفق
- `compileall` سورس Python: موفق
- کنترل SHA-256 و صحت ZIP داخلی: موفق

**محدودیت تأیید:** در محیط ساخت حاضر Docker daemon و کتابخانه‌های کامل پروژه در دسترس نیستند. بیلد واقعی Railway و اجرای مجدد کل مجموعه آزمون‌ها انجام نشده است. به همین دلیل `QUALITY_PROOF.json` و `RELEASE_MANIFEST.json` برای سورس اصلاح‌شده عمداً وضعیت `UNVERIFIED_UNTIL_RAILWAY_QUALITY_STAGE` دارند؛ اثبات موفقیت تست‌های checkpoint قبلی برای این سورس جدید بازاستفاده نشده است. لایهٔ quality در خود `Dockerfile` هنگام Build آزمون‌های کامل را دوباره اجرا می‌کند.

## روش نصب در Railway
1. فایل ZIP نهایی را از حالت فشرده خارج کنید و **محتوای داخل آن** (از جمله هر سه فایل `Dockerfile`، `sentinel_runtime.zip` و `sentinel_runtime.zip.sha256`) را در ریشهٔ مخزن GitHub قرار دهید؛ قرار دادن خود فایل ZIP بدون استخراج کافی نیست.
2. در Railway سرویس برنامه، Builder از نوع Dockerfile باشد و مسیر Dockerfile برابر `Dockerfile` بماند.
3. تغییرات را Commit و Deploy کنید؛ از گزینهٔ Rebuild/Deploy بدون اتکا به کش قبلی استفاده کنید تا Dockerfile جدید اعمال شود.
4. اگر دوباره خطا مشاهده شد، **چند خط قبل و بعد از اولین `E:` یا `ERROR` و همچنین انتهای Build Log** را بررسی کنید. عبارت `cached` و همچنین خط `+ attempts=0` به تنهایی خطای نهایی نیستند.

هیچ کلید API، توکن، اطلاعات دیتابیس، منطق معاملاتی یا تنظیمات RailWay خصوصی در این اصلاح تغییر داده نشده است.
