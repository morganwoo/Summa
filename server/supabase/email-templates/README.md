# Summa email templates

`confirm-signup.html` is the branded confirmation email.

1. Supabase dashboard > Authentication > Emails > Templates > **Confirm signup**.
2. Subject: `Welcome to Summa — Your Next 90 Days`
3. Replace the message body with the full contents of `confirm-signup.html` and save.

The button uses Supabase's `{{ .ConfirmationURL }}` placeholder, so the link, the
`summa://auth/callback` redirect, and the sign-in flow are unchanged.

## Sender name

The sender shown as "Supabase Auth" belongs to Supabase's built-in mail service and cannot be
renamed. To send as **Summa**, enable custom SMTP (Authentication > Emails > SMTP Settings) with
a mail provider and a domain you own, and set Sender name to `Summa`. The SMTP password is entered
only in the Supabase dashboard; it never goes in this repository or the app.
