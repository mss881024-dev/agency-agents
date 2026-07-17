# Changbook Modernization — a small consortium at work

**Client**: 도서출판 창 (Changbook Publishing) — a Seoul publisher of handwriting/calligraphy
workbooks, foreign-language phrasebooks, sudoku/coloring brain-game books, and Korean classics.
**Source**: `www.changbook.com/skin_ws1/` — a legacy PHP shopping-mall skin (`product_view.php`,
base64-encoded `goods_data` query params, table-based product listings, no responsive layout).
**Deliverable**: [`index.html`](./index.html) — a single self-contained, mobile-first storefront
front end covering the same three catalog sections the original site exposed.

This wasn't a solo rebuild. Four specialist lenses from [The Agency](../../README.md) roster were
run against the brief in sequence, each handing findings to the next:

| Lens | Agent | Verdict feeding into the next stage |
|---|---|---|
| Research | [UX Researcher](../../design/design-ux-researcher.md) | Original page is a bare HTML `<table>` dump: no nav, no filtering, no mobile layout, prices unformatted, one dead link (`-` price on 전통 관혼상제). Three catalog groups (베스트셀러/신간도서/추천도서) are the only real information architecture worth keeping — everything else is presentation debt. |
| Identity | [Brand Guardian](../../design/design-brand-guardian.md) | Publisher name 창 (窓, "window") was sitting unused as pure metadata. Made it the organizing metaphor — a window you open onto learning — instead of inventing generic "modern bookstore" branding with no tie to this client. |
| Visual system | [UI Designer](../../design/design-ui-designer.md) | v1 used a muted ink-and-hanji palette (warm paper, sumi ink, celadon, seal-stamp red) tied to the publisher's traditional catalog — client feedback called it "옛날 느낌" (dated), wanting current Korean web-design energy instead. v2: pure white/near-black neutrals, bold Pretendard weights (800/900), a vivid coral + violet + mint accent system, pill-shaped nav/tabs/buttons, 20px card radii, soft blurred hero gradients — the palette Korean D2C/app brands (Toss, Danggeun, Class101) actually ship today. Genre-tinted card spines carried over as the lightweight taxonomy the original site never had. |
| Build | [Frontend Developer](../../engineering/engineering-frontend-developer.md) | Static, dependency-free HTML/CSS/JS. Client-side category tabs + live search. Preserves every real `product_view.php` deep link so "바로가기" still routes to the live backend — this is a front-end reskin, not a backend rewrite. |

## What changed vs. the original

- **Responsive, mobile-first layout** — the original was a fixed `<table>`; this is a card grid
  that reflows from 1 to 5 columns depending on viewport.
- **Navigation + filtering** — sticky header, category tabs (전체/베스트셀러/신간도서/추천도서),
  and instant client-side search by title. None of this existed before.
- **Genre tagging** — each of the 28 titles was tagged (한자·서예 / 외국어 / 두뇌·스도쿠 /
  두뇌·컬러링 / 인문·고전 / 건강·생활백과 / 자기계발) directly from its title text, giving
  visitors a way to browse by topic that the flat table never offered.
- **Honest price handling** — the one row with a `-` price now reads "가격문의" instead of a
  bare dash.
- **Legal/business footer preserved verbatim** — 상호, 대표자, 사업자등록번호, 주소, 전화,
  이메일, copyright line are unchanged from the source, as required for Korean
  통신판매업 disclosure.
- **Dark mode + accessibility** — token-based theme that respects `prefers-color-scheme` and an
  explicit toggle hook (`data-theme`), visible focus states, `prefers-reduced-motion` guard on
  the one decorative animation.

## What this is *not*

This is a **front-end reskin**, not a rebuild of the checkout/cart/admin backend. All "바로가기"
links point at the real `product_view.php` endpoints on changbook.com, base64 `goods_data` and
all — the existing PHP mall still needs to serve those pages. Product cover images aren't
included because none were available from the source; card spines use color/typography instead
of fabricated photography. CJK web fonts are not loaded from a CDN (the Artifact sandbox this was
also previewed in blocks font CDNs, and self-hosting a full Korean glyph set as a data URI is
impractical) — the type stack instead relies on the Korean system fonts every target OS already
ships (Apple SD Gothic Neo, Malgun Gothic, Pretendard where installed).

## Viewing it

Open `index.html` directly in a browser — no build step, no dependencies.
