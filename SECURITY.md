# Повідомлення про вразливості / Security policy

Не публікуй паролі, токени, координати, резервні копії або опис придатної до
зловживання вразливості у відкритих Issues. Нижче — спосіб узгодити приватне повідомлення.

## Reporting

1. Open the repository's [Security advisories](https://github.com/DimasikBog/AMID-Offgrid/security/advisories).
2. If **Report a vulnerability** is available, use that private reporting flow.
3. If it is absent, create an [issue](https://github.com/DimasikBog/AMID-Offgrid/issues/new)
   asking for a private security contact. Include no exploit details or sensitive data;
   wait for a maintainer to agree a private channel before sharing them.

Private vulnerability reporting is a separate GitHub setting. This policy does
not enable it and does not claim that it is currently enabled.
[GitHub reporting guidance](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/report-privately).

Include the exact version/commit, affected platform, a minimal reproduction
with synthetic data and the impact. Use the latest public candidate when possible;
there is no advertised LTS or guaranteed response time. Do not disclose real
coordinates, account identifiers, passwords, access/refresh tokens, TOTP secrets,
recovery codes, private signing keys, personal audio or complete backups.

Areas include account authentication, offline profiles/backups, imports,
download integrity, PWA cache, local model handling and radio message processing.
Never test emergency delivery with real calls or SMS to emergency services.
Use fakes or the explicit SOS training mode.

A public repository exposes source code; it is not a request to publish personal
data or credentials. Production signing and server secrets must remain outside
public commits. [Privacy details](docs/PRIVACY.md) · [SOS limits](docs/EMERGENCY_SOS.md).
