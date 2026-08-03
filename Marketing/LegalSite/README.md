# Circular Studios legal site

Static, dependency-free pages for Towering Tower:

- `/privacy/` — use this as Steamworks' **Privacy Policy URL**.
- `/health/` — use this as Steamworks' **Health Warning URL**.

## Required before publishing

1. Own or configure the domain you plan to use. The draft assumes `circularstudios.games`.
2. Create and monitor `privacy@circularstudios.games` and `support@circularstudios.games`, or replace both addresses in the HTML with real monitored addresses.
3. Review `DATA_AUDIT.md`, especially the Steamworks portal settings that cannot be verified from this repository.
4. Confirm the effective date and have the privacy wording reviewed for the countries where the game will be offered. This draft is not a substitute for legal advice.
5. Deploy the contents of this directory as the site root and test every link over HTTPS.

## Hosting

The site has no build step and can be deployed to any static host. A custom domain with Cloudflare Pages, GitHub Pages, or another reputable provider is sufficient.

For clean Steam URLs, publish it so these addresses resolve directly:

```text
https://circularstudios.games/privacy/
https://circularstudios.games/health/
```

The site intentionally includes no JavaScript, analytics, forms, remote fonts, or cookies. If those are added later, update both the privacy policy and `DATA_AUDIT.md` before deployment.

## Local preview

Opening `index.html` directly works for a quick visual check. To verify clean directory URLs, serve this directory through any local static-file server and visit `/privacy/` and `/health/`.
