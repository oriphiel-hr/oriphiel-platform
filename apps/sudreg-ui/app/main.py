from __future__ import annotations

from pathlib import Path

from fastapi import Depends, FastAPI, Form, Query, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from starlette.middleware.sessions import SessionMiddleware

from .auth import (
    LoginRequired,
    login_redirect_url,
    logout,
    require_user,
    require_user_or_basic,
    session_user,
    verify_password,
)
from .config import settings
from . import db
from . import website_finder
from .nkd import format_activity

BASE = Path(__file__).resolve().parent

app = FastAPI(title="Sudreg UI", docs_url=None, redoc_url=None)
app.add_middleware(
    SessionMiddleware,
    secret_key=settings.session_secret,
    session_cookie="sudreg_ui",
    same_site="lax",
    https_only=False,
    max_age=60 * 60 * 12,
)
app.mount("/static", StaticFiles(directory=BASE / "static"), name="static")
templates = Jinja2Templates(directory=str(BASE / "templates"))
templates.env.filters["activity_label"] = format_activity


@app.exception_handler(LoginRequired)
async def login_required_handler(request: Request, exc: LoginRequired):
    return RedirectResponse(login_redirect_url(exc.next_url), status_code=303)


@app.get("/health")
def health():
    return {"ok": True}

@app.get("/login", response_class=HTMLResponse)
def login_page(request: Request, next: str = "/"):
    if session_user(request):
        return RedirectResponse(next or "/", status_code=303)
    return templates.TemplateResponse(
        request,
        "login.html",
        {"error": None, "next": next or "/"},
    )


@app.post("/login")
def login_submit(
    request: Request,
    username: str = Form(...),
    password: str = Form(...),
    next: str = Form("/"),
):
    if verify_password(username, password):
        request.session["user"] = username
        return RedirectResponse(next or "/", status_code=303)
    return templates.TemplateResponse(
        request,
        "login.html",
        {"error": "Pogrešan username ili lozinka.", "next": next or "/"},
        status_code=401,
    )


@app.get("/logout")
def logout_route(request: Request):
    logout(request)
    return RedirectResponse("/login", status_code=303)


@app.get("/", response_class=HTMLResponse)
def index(
    request: Request,
    q: str | None = Query(None),
    status: str | None = Query(None),
    activity: str | None = Query(None),
    include_deleted: bool = Query(False),
    page: int = Query(1, ge=1),
    page_size: int = Query(None),
    _user: str = Depends(require_user),
):
    size = page_size or settings.page_size_default
    db_error = None
    result = {
        "rows": [],
        "total": 0,
        "page": page,
        "page_size": size,
        "pages": 1,
        "has_prev": False,
        "has_next": False,
    }
    stats = {}
    statuses: list[str] = []
    activities: list[dict] = []
    try:
        result = db.list_companies(
            q=q,
            status=status or None,
            activity=activity or None,
            include_deleted=include_deleted,
            page=page,
            page_size=size,
        )
        stats = db.db_stats()
        statuses = db.list_statuses()
        activities = db.list_activity_options()
    except Exception as e:
        db_error = str(e)

    return templates.TemplateResponse(
        request,
        "index.html",
        {
            "q": q or "",
            "status": status or "",
            "activity": activity or "",
            "include_deleted": include_deleted,
            "statuses": statuses,
            "activities": activities,
            "stats": stats,
            "user": _user,
            "db_error": db_error,
            **result,
        },
    )


@app.get("/company/{mbs}", response_class=HTMLResponse)
def company_detail(
    request: Request,
    mbs: str,
    _user: str = Depends(require_user),
):
    try:
        data = db.get_company(mbs)
    except Exception as e:
        return templates.TemplateResponse(
            request,
            "index.html",
            {
                "q": "",
                "status": "",
                "include_deleted": False,
                "statuses": [],
                "stats": {},
                "user": _user,
                "db_error": str(e),
                "rows": [],
                "total": 0,
                "page": 1,
                "page_size": 25,
                "pages": 1,
                "has_prev": False,
                "has_next": False,
            },
            status_code=503,
        )
    if not data:
        return templates.TemplateResponse(
            request,
            "not_found.html",
            {"mbs": mbs, "user": _user},
            status_code=404,
        )
    return templates.TemplateResponse(
        request,
        "company.html",
        {"user": _user, **data},
    )


@app.get("/web-finder", response_class=HTMLResponse)
def web_finder(
    request: Request,
    mbs: str | None = Query(None),
    run: str | None = Query(None),
    saved: str | None = Query(None),
    _user: str = Depends(require_user),
):
    company = None
    find = None
    error = None
    ran = False
    mbs_val = (mbs or "").strip()
    if mbs_val:
        try:
            data = db.get_company(mbs_val)
            if not data:
                # try zero-padded
                data = db.get_company(mbs_val.zfill(9))
            if data:
                company = data["company"]
                mbs_val = company["mbs"]
            else:
                error = f"MBS {mbs_val} nije u bazi."
        except Exception as e:
            error = str(e)

    if company and run:
        ran = True
        try:
            find = website_finder.find_websites_for_company(company)
            if find.get("results"):
                find["results"] = website_finder.rank_results_for_company(
                    find["results"], company
                )
        except Exception as e:
            error = f"Pretraga nije uspjela: {e}"
            find = {"candidates_checked": 0, "results": [], "queries_note": ""}

    return templates.TemplateResponse(
        request,
        "web_finder.html",
        {
            "user": _user,
            "mbs": mbs_val,
            "company": company,
            "find": find,
            "ran": ran,
            "error": error,
            "saved": saved,
        },
    )


@app.post("/web-finder/save")
def web_finder_save(
    request: Request,
    mbs: str = Form(...),
    website: str = Form(...),
    is_primary: str = Form("1"),
    role: str = Form(""),
    _user: str = Depends(require_user),
):
    oib = None
    score = None
    confidence = None
    evidence_url = None
    try:
        data = db.get_company(mbs) or db.get_company(mbs.zfill(9))
        if data:
            oib = data["company"].get("oib")
            mbs = data["company"]["mbs"]
    except Exception:
        pass
    primary = (is_primary or "1").strip().lower() in {"1", "true", "yes", "on"}
    role_val = (role or "").strip() or None
    ok = db.update_company_website(
        mbs,
        website,
        oib=oib,
        verified_by=_user,
        is_primary=primary,
        role=role_val,
    )
    if not ok:
        return RedirectResponse(f"/web-finder?mbs={mbs}&run=1", status_code=303)
    from urllib.parse import quote

    return RedirectResponse(
        f"/web-finder?mbs={quote(mbs)}&saved={quote(website)}",
        status_code=303,
    )


@app.get("/web-batch", response_class=HTMLResponse)
def web_batch(
    request: Request,
    _user: str = Depends(require_user),
):
    from . import crm

    error = None
    jobs: list = []
    active = None
    stats = {}
    try:
        active = crm.get_active_job()
        jobs = crm.get_latest_jobs(8)
        stats = crm.job_stats()
    except Exception as e:
        error = str(e)
    return templates.TemplateResponse(
        request,
        "web_batch.html",
        {
            "user": _user,
            "active": active,
            "jobs": jobs,
            "stats": stats,
            "error": error,
            "flash": request.query_params.get("msg"),
        },
    )


@app.post("/web-batch/start")
def web_batch_start(
    request: Request,
    max_companies: int = Form(500),
    only_with_email: str | None = Form(None),
    auto_save_min_score: int = Form(60),
    _user: str = Depends(require_user),
):
    from . import crm
    from urllib.parse import quote

    try:
        job = crm.create_web_finder_job(
            started_by=_user,
            only_with_email=bool(only_with_email),
            max_companies=max(1, min(int(max_companies or 500), 50000)),
            auto_save_min_score=max(30, min(int(auto_save_min_score or 60), 200)),
        )
        msg = quote(f"Posao #{job['id']} u redu — VPS worker ga preuzima.")
    except Exception as e:
        msg = quote(str(e))
    return RedirectResponse(f"/web-batch?msg={msg}", status_code=303)


@app.post("/web-batch/pause")
def web_batch_pause(
    request: Request,
    job_id: int = Form(...),
    _user: str = Depends(require_user),
):
    from . import crm
    from urllib.parse import quote

    crm.set_job_status(int(job_id), "paused", "Pauzirano iz UI")
    return RedirectResponse(
        f"/web-batch?msg={quote(f'Posao #{job_id} pauziran')}",
        status_code=303,
    )


@app.post("/web-batch/resume")
def web_batch_resume(
    request: Request,
    job_id: int = Form(...),
    _user: str = Depends(require_user),
):
    from . import crm
    from urllib.parse import quote

    with crm.get_crm_conn() as conn:
        active = conn.execute(
            """
            SELECT id FROM web_finder_jobs
            WHERE status IN ('queued', 'running') AND id <> %s
            LIMIT 1
            """,
            (job_id,),
        ).fetchone()
        if active:
            return RedirectResponse(
                f"/web-batch?msg={quote('Već postoji drugi aktivan posao')}",
                status_code=303,
            )
        conn.execute(
            """
            UPDATE web_finder_jobs
            SET status = 'queued',
                finished_at = NULL,
                last_message = 'Ponovno u redu (resume)',
                updated_at = NOW()
            WHERE id = %s AND status = 'paused'
            """,
            (job_id,),
        )
        conn.commit()
    return RedirectResponse(
        f"/web-batch?msg={quote(f'Posao #{job_id} ponovno u redu')}",
        status_code=303,
    )


@app.get("/api/companies")
def api_companies(
    q: str | None = None,
    status: str | None = None,
    activity: str | None = None,
    include_deleted: bool = False,
    page: int = Query(1, ge=1),
    page_size: int = Query(None),
    _user: str = Depends(require_user_or_basic),
):
    size = page_size or settings.page_size_default
    return db.list_companies(
        q=q,
        status=status,
        activity=activity,
        include_deleted=include_deleted,
        page=page,
        page_size=size,
    )


@app.get("/api/activities")
def api_activities(_user: str = Depends(require_user_or_basic)):
    return db.list_activity_options()


@app.get("/api/companies/{mbs}")
def api_company(mbs: str, _user: str = Depends(require_user_or_basic)):
    from fastapi import HTTPException

    data = db.get_company(mbs)
    if not data:
        raise HTTPException(status_code=404, detail="Not found")
    return data


def main():
    import uvicorn

    uvicorn.run(
        "app.main:app",
        host=settings.host,
        port=settings.port,
        reload=False,
    )


if __name__ == "__main__":
    main()
