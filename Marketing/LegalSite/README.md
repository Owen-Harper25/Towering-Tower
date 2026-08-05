# Circular Studios legal site

Static, dependency-free pages for Towering Tower:

- `/privacy/` — use this as Steamworks' **Privacy Policy URL**.
- `/health/` — use this as Steamworks' **Health Warning URL**.

## Required before publishing

1. Confirm the final public URL supplied by the hosting provider or connect a custom domain later.
2. Monitor `circulargamestudios@outlook.com`; it is the published privacy, support, accessibility, and safety contact.
3. Review `DATA_AUDIT.md`, especially the Steamworks portal settings that cannot be verified from this repository.
4. Confirm the effective date and have the privacy wording reviewed for the countries where the game will be offered. This draft is not a substitute for legal advice.
5. Deploy the contents of this directory as the site root and test every link over HTTPS.

## Hosting

The site has no build step and can be deployed to any static host. A custom domain with Cloudflare Pages, GitHub Pages, or another reputable provider is sufficient.

The included GitHub Pages workflow publishes this directory as the site root. Without a custom domain, the expected project-site addresses are:

```text
https://owen-harper25.github.io/Towering-Tower/privacy/
https://owen-harper25.github.io/Towering-Tower/health/
```

In the GitHub repository, open **Settings → Pages** and set **Source** to **GitHub Actions** once. The workflow at `.github/workflows/deploy-legal-site.yml` handles later deployments from `main` automatically.

The site intentionally includes no JavaScript, analytics, forms, remote fonts, or cookies. If those are added later, update both the privacy policy and `DATA_AUDIT.md` before deployment.

## Local preview

Opening `index.html` directly works for a quick visual check. To verify clean directory URLs, serve this directory through any local static-file server and visit `/privacy/` and `/health/`.
