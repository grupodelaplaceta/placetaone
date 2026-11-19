# ADR-002: los bonos RBU caducan a los 3 meses si no se canjean

- Estado: aprobado por la Junta según la instrucción del 2026-11-19. Firma del responsable: pendiente.
- Contexto: el bono caducaba a los 7 días. Las cantidades no reclamadas vuelven a la Reserva al caducar, y el plazo corto deja fuera a quien no puede canjear a tiempo.
- Decisión: `plone27_rbu_issue_week` fija `expires_on = semana + 3 meses` (migración 0060). Los bonos disponibles existentes se alinean al mismo plazo.
- Consecuencia que hay que decidir: el saldo canjeado caduca el mismo día que su bono (`lote.expires_on = bono.expires_on`). Un bono canjeado cerca del final del plazo tendrá poco tiempo para gastarse. Opciones: mantenerlo así, o dar un plazo de gasto propio desde el canje (por ejemplo, 30 días). Pendiente de decisión.
- Verificación: SQL estático y verificación del repositorio en verde. No ejecutado en PostgreSQL.
