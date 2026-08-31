from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    database_url: str = "postgresql://oriphiel@127.0.0.1:5432/sudreg"
    # Ako prazno: isti host/user kao DATABASE_URL, baza oriphiel_crm
    crm_database_url: str = ""
    sudreg_ui_user: str = "admin"
    sudreg_ui_password: str = "changeme"
    session_secret: str = "sudreg-ui-dev-secret-change-me"
    host: str = "127.0.0.1"
    port: int = 8091
    page_size_default: int = 25
    page_size_max: int = 100


settings = Settings()
