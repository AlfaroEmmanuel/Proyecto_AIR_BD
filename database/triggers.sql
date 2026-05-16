
-- TRIGGER 1: PREVENCIÓN DE TRASLAPE
-- Regla de negocio: Un asambleísta NO puede tener dos nombramientos con
-- estado_activo = TRUE al mismo tiempo, sin importar el sector o periodo.

CREATE OR REPLACE FUNCTION fn_validar_traslape_nombramiento()
RETURNS TRIGGER AS $$
DECLARE
    v_conflictos INT;
BEGIN
    -- Solo aplica cuando el nombramiento que se intenta insertar/actualizar está activo
    IF NEW.estado_activo = TRUE THEN

        SELECT COUNT(*) INTO v_conflictos
        FROM nombramiento
        WHERE cedula_asambleista = NEW.cedula_asambleista
          AND estado_activo      = TRUE
          -- En UPDATE, excluye el propio registro para no compararse consigo mismo
          AND id_nombramiento   != COALESCE(NEW.id_nombramiento, -1);

        IF v_conflictos > 0 THEN
            RAISE EXCEPTION
                'TRASLAPE DETECTADO: El asambleísta con cédula % ya tiene un '
                'nombramiento activo. Debe desactivar el nombramiento vigente '
                'antes de crear o activar uno nuevo.',
                NEW.cedula_asambleista;
        END IF;

    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE TRIGGER trg_validar_traslape_nombramiento
    BEFORE INSERT OR UPDATE ON nombramiento
    FOR EACH ROW
    EXECUTE FUNCTION fn_validar_traslape_nombramiento();


-- TRIGGER 2: VALIDACIÓN DE FECHA DE NOMBRAMIENTO
-- Regla de negocio: La fecha del nombramiento debe estar dentro del rango
-- del periodo de gestión al que se vincula.

CREATE OR REPLACE FUNCTION fn_validar_fecha_nombramiento()
RETURNS TRIGGER AS $$
DECLARE
    v_inicio DATE;
    v_fin    DATE;
BEGIN
    SELECT fecha_inicio, fecha_fin
      INTO v_inicio, v_fin
      FROM periodo_gestion
     WHERE id_periodo = NEW.id_periodo;

    IF NEW.fecha_nombramiento < v_inicio OR NEW.fecha_nombramiento > v_fin THEN
        RAISE EXCEPTION
            'FECHA INVÁLIDA: La fecha de nombramiento (%) está fuera del '
            'rango del periodo de gestión (% al %).',
            NEW.fecha_nombramiento,
            v_inicio,
            v_fin;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE TRIGGER trg_validar_fecha_nombramiento
    BEFORE INSERT OR UPDATE ON nombramiento
    FOR EACH ROW
    EXECUTE FUNCTION fn_validar_fecha_nombramiento();