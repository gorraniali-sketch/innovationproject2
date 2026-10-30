# جوانه

سامانه‌ی ایده‌یابی اجتماعی با ثبت‌نام ایمیلی و تأیید ایمیل در Supabase Auth.

## راه‌اندازی محلی

1. وابستگی‌ها را نصب کنید و `.env.example` را به `.env.local` کپی کنید.
2. در `.env.local` این موارد را از بخش **Connect** پروژه‌ی Supabase وارد کنید:
   - `NEXT_PUBLIC_SUPABASE_URL`
   - `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`
   - `NEXT_PUBLIC_SITE_URL` (برای توسعه: `http://localhost:3000`)
3. در داشبورد Supabase، در **Authentication → Sign In / Providers → Email** ورود ایمیلی را فعال و تأیید ایمیل را الزامی کنید.
4. در **Authentication → URL Configuration**، مقدار **Site URL** را برابر `NEXT_PUBLIC_SITE_URL` قرار دهید و هر دو redirect کامل زیر را برای محیط مربوطه به فهرست مجاز اضافه کنید:
   - توسعه: `http://localhost:3000/auth/callback?next=%2Fauth%2Fconfirmed`
   - توسعه: `http://localhost:3000/auth/callback?next=%2Fauth%2Fupdate-password`
   - انتشار: همین دو URL با دامنه‌ی واقعی و HTTPS
5. در **Authentication → Email Templates**، پیوند قالب‌های تأیید ثبت‌نام و بازیابی رمز عبور را روی `{{ .ConfirmationURL }}` نگه دارید تا redirect تعیین‌شده در درخواست حفظ و کد PKCE به `/auth/callback` برگردانده شود. اگر قالب را سفارشی می‌کنید، redirect خود برنامه را حفظ کنید؛ الگوی token hash با callback فعلی سازگار نیست. برای قالب‌هایی که URL را دستی می‌سازند، مستندات Supabase درباره‌ی استفاده از `{{ .RedirectTo }}` را دنبال کنید.
6. برنامه را اجرا کنید:

   ```sh
   npm run dev
   ```

کلید publishable عمومی است؛ هرگز کلید `service_role` را در متغیرهای محیطی این برنامه قرار ندهید. تا وقتی متغیرهای Supabase تنظیم نشده باشند، صفحه‌ی اصلی و ایده‌یابی عمومی در دسترس می‌مانند و عملیات احراز هویت پیام کنترل‌شده نشان می‌دهد. تنظیمات داشبورد یا پروژه‌ی راه دور از این مخزن تغییر داده نشده‌اند.

## مسیرهای احراز هویت

| مسیر | کاربرد |
| --- | --- |
| `/auth/sign-up` | ثبت‌نام و درخواست تأیید ایمیل |
| `/auth/sign-in` | ورود با ایمیل و رمز عبور |
| `/auth/callback` | مبادله‌ی امن کد PKCE پس از تأیید ایمیل یا بازنشانی |
| `/auth/confirmed` | پیام تأیید ایمیل |
| `/auth/resend-confirmation` | درخواست دوباره‌ی ایمیل تأیید با فاصله‌ی حداقل ۶۰ ثانیه در همان مرورگر |
| `/auth/forgot-password` | درخواست ایمیل بازیابی |
| `/auth/update-password` | انتخاب رمز تازه پس از callback معتبر |
| `/auth/sign-out` | پاک‌کردن نشست |

ایمیل بازیابی و درخواست تأیید، وجود حساب را افشا نمی‌کنند. محدودیت محلی ارسال مجدد مکمل محدودیت‌های نرخ Supabase است. فرم ایده‌یابی همچنان داده‌ها را فقط در حافظه‌ی همان صفحه نگه می‌دارد و به دیتابیس وصل نشده است.

## بررسی محلی

```sh
npm run lint
./node_modules/.bin/tsc --noEmit --incremental false
npm run build
node --experimental-strip-types --test tests/auth-validation.test.mjs
```

این بررسی‌ها به پیکربندی واقعی Supabase نیاز ندارند و ارسال ایمیل یا ثبت‌نام واقعی را آزمایش نمی‌کنند.
