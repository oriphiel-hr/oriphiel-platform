from __future__ import annotations

import re
from html import unescape
from typing import Any
from urllib.parse import parse_qs, quote_plus, unquote, urljoin, urlparse

import httpx

UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
)

# Društvene mreže, pretraživači, Sudreg — i HR/EU poslovni agregatori (imenici firmi)
SKIP_HOSTS = {
    "sudreg.pravosudje.hr",
    "pravosudje.hr",
    "facebook.com",
    "www.facebook.com",
    "linkedin.com",
    "www.linkedin.com",
    "instagram.com",
    "www.instagram.com",
    "twitter.com",
    "x.com",
    "youtube.com",
    "maps.google.com",
    "google.com",
    "www.google.com",
    "duckduckgo.com",
    "bing.com",
    "www.bing.com",
    # HR / regionalni imenici i agregatori
    "crobiz.net",
    "www.crobiz.net",
    "crobiz.hr",
    "firmoteka.hr",
    "poslovna.hr",
    "fininfo.hr",
    "companywall.hr",
    "biznet.hr",
    "isplate.info",
    "poslovni.hr",
    "business.hr",
    "zlatne-stranice.hr",
    "zlatnestranice.hr",
    "imenik.hr",
    "hgk.hr",
    "komora.hr",
    "bisnode.hr",
    "creditreform.hr",
    "fina.hr",
    "infobiro.hr",
    "tvrtke.com",
    "poduzetnistvo.org",
    "moj-posao.net",
    "njuskalo.hr",
    "bolha.com",
    # međunarodni agregatori / registry mirror
    "opencorporates.com",
    "northdata.com",
    "northdata.de",
    "crunchbase.com",
    "dnb.com",
    "bloomberg.com",
    "wikipedia.org",
    "wikidata.org",
    "yelp.com",
    "tripadvisor.com",
}

# Domene / sufiksi: host koji završava ovime ili sadrži segment = agregator
SKIP_HOST_SUFFIXES = (
    "crobiz.net",
    "crobiz.hr",
    "firmoteka.hr",
    "poslovna.hr",
    "fininfo.hr",
    "companywall.hr",
    "biznet.hr",
    "isplate.info",
    "opencorporates.com",
    "northdata.com",
    "northdata.de",
    "crunchbase.com",
)

SKIP_HOST_KEYWORDS = (
    "crobiz",
    "firmoteka",
    "companywall",
    "fininfo",
    "biznet",
    "isplate",
    "opencorporates",
    "northdata",
    "creditreform",
    "bisnode",
)


def _host_key(url_or_host: str) -> str:
    raw = (url_or_host or "").strip().lower()
    if "://" in raw:
        raw = urlparse(raw).netloc
    return raw.split("@")[-1].split(":")[0].removeprefix("www.")


def is_skipped_host(url_or_host: str) -> bool:
    host = _host_key(url_or_host)
    if not host:
        return True
    if host in SKIP_HOSTS or f"www.{host}" in SKIP_HOSTS:
        return True
    for suf in SKIP_HOST_SUFFIXES:
        if host == suf or host.endswith("." + suf):
            return True
    parts = host.split(".")
    for kw in SKIP_HOST_KEYWORDS:
        if any(kw in part for part in parts[:-1]) or (len(parts) >= 2 and kw in parts[-2]):
            return True
    return False



def _norm_text(s: str) -> str:
    s = unescape(s or "")
    s = re.sub(r"\s+", " ", s).strip().lower()
    return s


def _digits(s: str) -> str:
    return "".join(ch for ch in (s or "") if ch.isdigit())


def email_domain_candidates(email: str | None) -> list[str]:
    if not email or "@" not in email:
        return []
    domain = email.split("@", 1)[1].strip().lower().removeprefix("www.")
    if not domain or domain in {"gmail.com", "hotmail.com", "outlook.com", "yahoo.com", "inet.hr"}:
        return []
    # Jedan kandidat (bez www duplikata); redirect će pokazati kanonsku varijantu
    return [f"https://{domain}/"]


def site_root(url: str) -> str | None:
    """Kanonski root bez www: https://example.hr/"""
    try:
        p = urlparse(url)
        if p.scheme not in {"http", "https"} or not p.netloc:
            return None
        host = _host_key(p.netloc)
        if not host:
            return None
        return f"https://{host}/"
    except Exception:
        return None


def search_duckduckgo(query: str, limit: int = 8) -> list[str]:
    urls: list[str] = []
    try:
        with httpx.Client(timeout=20.0, follow_redirects=True, headers={"User-Agent": UA}) as client:
            r = client.post(
                "https://html.duckduckgo.com/html/",
                data={"q": query},
            )
            r.raise_for_status()
            html = r.text
    except Exception:
        return urls

    for m in re.finditer(r'uddg=([^&"]+)', html):
        raw = unquote(m.group(1))
        if raw.startswith("http"):
            urls.append(raw.split("&")[0])
    for m in re.finditer(r'class="result__a"[^>]*href="([^"]+)"', html):
        href = unescape(m.group(1))
        if "uddg=" in href:
            qs = parse_qs(urlparse(href).query)
            if "uddg" in qs:
                urls.append(unquote(qs["uddg"][0]))
        elif href.startswith("http"):
            urls.append(href)

    out: list[str] = []
    seen: set[str] = set()
    for u in urls:
        if is_skipped_host(u):
            continue
        root = site_root(u)
        if not root:
            continue
        host = _host_key(root)
        if not host or host in seen:
            continue
        seen.add(host)
        out.append(root)
        if len(out) >= limit:
            break
    return out


def collect_candidate_urls(company: dict[str, Any]) -> list[str]:
    naziv = (company.get("naziv") or company.get("naziv_kraci") or "").strip()
    oib = _digits(company.get("oib") or "")
    mbs = _digits(company.get("mbs") or "")
    email = company.get("email")

    candidates: list[str] = []
    candidates.extend(email_domain_candidates(email))

    queries = []
    if naziv and oib:
        queries.append(f'"{naziv}" {oib}')
        queries.append(f'"{naziv}" OIB {oib} kontakt')
    if naziv and mbs:
        queries.append(f'"{naziv}" MBS {mbs}')
    if naziv:
        queries.append(f'"{naziv}" službene stranice')

    for q in queries[:3]:
        candidates.extend(search_duckduckgo(q, limit=6))

    expanded: list[str] = []
    seen_hosts: set[str] = set()
    for u in candidates:
        try:
            if is_skipped_host(u):
                continue
            root = site_root(u)
            if not root or is_skipped_host(root):
                continue
            host = _host_key(root)
            if host in seen_hosts:
                continue
            seen_hosts.add(host)
            expanded.append(root)
        except Exception:
            continue
    return expanded[:20]


def page_paths_for(base: str) -> list[str]:
    root = base if base.endswith("/") else base.rsplit("/", 1)[0] + "/"
    parsed = urlparse(base)
    origin = f"{parsed.scheme}://{parsed.netloc}"
    paths = [
        base,
        origin + "/",
        origin + "/kontakt",
        origin + "/kontakt/",
        origin + "/contact",
        origin + "/o-nama",
        origin + "/o-nama/",
        origin + "/about",
        origin + "/about-us",
        origin + "/impressum",
        origin + "/tvrtka",
    ]
    # unique preserve order
    out: list[str] = []
    seen: set[str] = set()
    for p in paths:
        if p not in seen:
            seen.add(p)
            out.append(p)
    return out


def fetch_text(url: str) -> tuple[str | None, str | None, str | None]:
    """Vrati (tekst, greška, final_url nakon redirecta)."""
    try:
        with httpx.Client(timeout=12.0, follow_redirects=True, headers={"User-Agent": UA}) as client:
            r = client.get(url)
            if r.status_code >= 400:
                return None, f"HTTP {r.status_code}", None
            ctype = (r.headers.get("content-type") or "").lower()
            if "html" not in ctype and "text" not in ctype:
                return None, "not html", None
            text = r.text
            text = re.sub(r"(?is)<script[^>]*>.*?</script>", " ", text)
            text = re.sub(r"(?is)<style[^>]*>.*?</style>", " ", text)
            text = re.sub(r"(?is)<[^>]+>", " ", text)
            text = _norm_text(text)
            final = str(r.url) if r.url else url
            return text[:200_000], None, final
    except Exception as e:
        return None, str(e), None


def score_page(
    text: str,
    *,
    oib: str,
    mbs: str,
    naziv: str,
    naziv_kraci: str | None,
) -> dict[str, Any]:
    hits: list[str] = []
    score = 0
    if oib and oib in text.replace(" ", ""):
        # also plain
        if oib in re.sub(r"\D", "", text) or oib in text:
            score += 45
            hits.append(f"OIB {oib}")
    if mbs:
        mbs_norm = mbs.zfill(9) if mbs.isdigit() else mbs
        compact = re.sub(r"\D", "", text)
        if mbs in text or mbs_norm in text or mbs in compact or mbs_norm in compact:
            score += 45
            hits.append(f"MBS {mbs}")
    for label, name in (("naziv", naziv), ("kraći naziv", naziv_kraci or "")):
        n = _norm_text(name)
        if len(n) >= 5 and n in text:
            score += 20 if label == "naziv" else 12
            hits.append(label)
            break
        # softer: first significant token sequence
        if len(n) >= 8:
            core = re.sub(r"\b(d\.o\.o\.|d\.d\.|j\.d\.o\.o\.)\b", "", n).strip()
            if len(core) >= 6 and core in text:
                score += 15
                hits.append(f"{label} (djelomično)")
                break
    return {"score": score, "hits": hits}


def find_websites_for_company(company: dict[str, Any]) -> dict[str, Any]:
    oib = _digits(company.get("oib") or "")
    mbs = _digits(company.get("mbs") or "")
    naziv = company.get("naziv") or ""
    naziv_kraci = company.get("naziv_kraci")

    candidates = collect_candidate_urls(company)
    results: list[dict[str, Any]] = []
    checked_hosts: set[str] = set()

    for cand in candidates:
        if is_skipped_host(cand):
            continue
        host = _host_key(cand)
        if not host or host in checked_hosts:
            continue
        checked_hosts.add(host)

        best: dict[str, Any] | None = None
        evidence_pages: list[dict[str, Any]] = []
        for page_url in page_paths_for(cand)[:6]:
            text, err, final_url = fetch_text(page_url)
            if not text:
                continue
            scored = score_page(
                text, oib=oib, mbs=mbs, naziv=naziv, naziv_kraci=naziv_kraci
            )
            if scored["score"] <= 0:
                continue
            evidence_pages.append(
                {"url": page_url, "score": scored["score"], "hits": scored["hits"]}
            )
            # Kanonski root: preferiraj URL nakon redirecta, bez www duplikata
            canon = site_root(final_url or page_url) or site_root(cand) or cand
            if best is None or scored["score"] > best["score"]:
                best = {
                    "website": canon,
                    "score": scored["score"],
                    "hits": scored["hits"],
                    "evidence_url": final_url or page_url,
                }
        if best:
            best["evidence_pages"] = evidence_pages
            conf = (
                "visoka"
                if best["score"] >= 60
                else "srednja"
                if best["score"] >= 30
                else "niska"
            )
            best["confidence"] = conf
            results.append(best)

    results.sort(key=lambda x: x["score"], reverse=True)
    return {
        "candidates_checked": len(checked_hosts),
        "results": results[:8],
        "queries_note": "DuckDuckGo + email domena; verifikacija OIB/MBS/naziv na stranicama",
    }


def infer_domain_role(host: str, email: str | None = None) -> str:
    """Heuristika uloge domene (corporate, shop, …)."""
    h = (host or "").lower()
    labels = h.split(".")
    sub = labels[0] if len(labels) > 2 else ""
    blob = h.replace(".", " ")

    if any(k in sub or k in blob for k in ("shop", "store", "trgovin", "webshop", "cart")):
        return "shop"
    if any(k in sub or k in blob for k in ("booking", "rezerv", "book", "appoint")):
        return "booking"
    if any(k in sub or k in blob for k in ("kampanj", "promo", "landing", "akcija")):
        return "campaign"
    if any(k in sub for k in ("old", "legacy", "stari", "archive")):
        return "legacy"

    if email and "@" in email:
        ed = email.split("@", 1)[1].lower().removeprefix("www.")
        if ed not in {"gmail.com", "hotmail.com", "outlook.com", "yahoo.com", "inet.hr"}:
            if _host_key(ed) == _host_key(h):
                return "corporate"
    return "corporate"


def primary_rank_score(result: dict[str, Any], company: dict[str, Any]) -> int:
    """Viši = vjerojatnije glavna domena."""
    base = int(result.get("score") or 0)
    host = _host_key(result.get("website") or "")
    role = infer_domain_role(host, company.get("email"))
    bonus = 0
    if role == "corporate":
        bonus += 15
    elif role == "shop":
        bonus -= 25
    elif role == "booking":
        bonus -= 20
    elif role == "campaign":
        bonus -= 15
    elif role == "legacy":
        bonus -= 10

    email = company.get("email") or ""
    if email and "@" in email:
        ed = email.split("@", 1)[1].lower().removeprefix("www.")
        if ed not in {"gmail.com", "hotmail.com", "outlook.com", "yahoo.com", "inet.hr"}:
            if _host_key(ed) == host:
                bonus += 20

    parts = host.split(".")
    if len(parts) == 2:
        bonus += 5
    if len(parts) > 2 and parts[0] not in {"www", "m", "mobile"}:
        bonus -= 8

    return base + bonus


def rank_results_for_company(
    results: list[dict[str, Any]], company: dict[str, Any]
) -> list[dict[str, Any]]:
    ranked = []
    for r in results:
        item = dict(r)
        host = _host_key(item.get("website") or "")
        item["role"] = infer_domain_role(host, company.get("email"))
        item["primary_rank"] = primary_rank_score(item, company)
        ranked.append(item)
    ranked.sort(key=lambda x: x.get("primary_rank") or 0, reverse=True)
    return ranked
