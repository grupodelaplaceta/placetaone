-- Placeta One · 0025 · Un diseño no puede publicarse en la API sin imagen.
-- Requiere 0024. Idempotente (el generador de instalación la hace reejecutable).
alter table plone27_card_designs add constraint plone27_design_publicado_imagen_ck
  check(not publicado_api or imagen_url is not null);
