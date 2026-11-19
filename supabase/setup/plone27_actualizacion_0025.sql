-- =====================================================================================================
-- PLACETA ONE · ACTUALIZACIÓN 0025 · Diseños publicables solo con imagen
-- REQUISITO: la base tiene aplicadas las migraciones 0001 a 0024.
-- Transacción única; reejecutable.
-- =====================================================================================================

begin;
-- Placeta One · 0025 · Un diseño no puede publicarse en la API sin imagen.
-- Requiere 0024. Idempotente (el generador de instalación la hace reejecutable).
do $$ begin alter table plone27_card_designs add constraint plone27_design_publicado_imagen_ck
  check(not publicado_api or imagen_url is not null) not valid; exception when duplicate_object then null; end $$;


do $$ begin raise notice 'Actualización 0025 aplicada correctamente.'; end $$;

commit;
