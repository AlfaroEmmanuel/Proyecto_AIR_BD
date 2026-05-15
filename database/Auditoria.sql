

-- FUNCIÓN GENÉRICA DE AUDITORÍA
-- Una sola función reutilizable para todas las tablas sensibles.
-- Captura: tabla afectada, operación, usuario de BD, fecha/hora,
--          estado anterior (OLD) y estado nuevo (NEW) en formato JSON.

CREATE OR REPLACE FUNCTION fn_registrar_auditoria()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO sys_log_auditoria (
        nombre_tabla,
        operacion,
        usuario_db,
        fecha_hora,
        datos_anteriores,
        datos_nuevos
    )
    VALUES (
        TG_TABLE_NAME,          -- Nombre de la tabla que disparó el trigger
        TG_OP,                  -- 'INSERT', 'UPDATE' o 'DELETE'
        CURRENT_USER,           -- Usuario conectado a la BD en ese momento
        CURRENT_TIMESTAMP,      -- Fecha y hora exacta del cambio
        CASE
            WHEN TG_OP = 'INSERT' THEN NULL         -- No hay estado anterior en INSERT
            ELSE row_to_json(OLD)                   -- Estado anterior en UPDATE y DELETE
        END,
        CASE
            WHEN TG_OP = 'DELETE' THEN NULL         -- No hay estado nuevo en DELETE
            ELSE row_to_json(NEW)                   -- Estado nuevo en INSERT y UPDATE
        END
    );

    -- En DELETE retorna OLD para no interrumpir la operación
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;



-- TRIGGERS DE AUDITORÍA POR TABLA SENSIBLE
-- Se aplican AFTER para no interferir con la operación principal.
-- Cubren INSERT, UPDATE y DELETE en cada tabla crítica.

-- --- Auditoría sobre asambleista ---
CREATE OR REPLACE TRIGGER trg_auditoria_asambleista
    AFTER INSERT OR UPDATE OR DELETE ON asambleista
    FOR EACH ROW
    EXECUTE FUNCTION fn_registrar_auditoria();

-- --- Auditoría sobre nombramiento ---
CREATE OR REPLACE TRIGGER trg_auditoria_nombramiento
    AFTER INSERT OR UPDATE OR DELETE ON nombramiento
    FOR EACH ROW
    EXECUTE FUNCTION fn_registrar_auditoria();

-- --- Auditoría sobre sector ---
CREATE OR REPLACE TRIGGER trg_auditoria_sector
    AFTER INSERT OR UPDATE OR DELETE ON sector
    FOR EACH ROW
    EXECUTE FUNCTION fn_registrar_auditoria();
