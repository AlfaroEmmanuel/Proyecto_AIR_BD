-- =============================================
-- Issue #10: Lógica de Versionamiento Normativo
-- Tabla oficial: elemento_normativo
-- =============================================

-- Evita que existan dos elementos vigentes con el mismo padre, tipo y número.
-- Ejemplo: no pueden existir dos ARTICULO 1 vigentes bajo el mismo CAPITULO.
CREATE UNIQUE INDEX IF NOT EXISTS idx_elemento_normativo_vigente
ON elemento_normativo (
    COALESCE(id_padre, -1),
    tipo,
    numero
)
WHERE estado = 'VIGENTE'
AND fecha_vigencia_fin IS NULL;


-- Función que marca la versión anterior como histórica
CREATE OR REPLACE FUNCTION fn_versionar_elemento_normativo()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.estado = 'VIGENTE' THEN
        UPDATE elemento_normativo
        SET estado = 'HISTORICO',
            fecha_vigencia_fin = CURRENT_DATE
        WHERE COALESCE(id_padre, -1) = COALESCE(NEW.id_padre, -1)
          AND tipo = NEW.tipo
          AND numero = NEW.numero
          AND estado = 'VIGENTE'
          AND fecha_vigencia_fin IS NULL;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- Se elimina el trigger si ya existía para evitar duplicados
DROP TRIGGER IF EXISTS trg_versionar_elemento_normativo
ON elemento_normativo;


-- Trigger que cierra la versión anterior antes de insertar la nueva
CREATE TRIGGER trg_versionar_elemento_normativo
BEFORE INSERT ON elemento_normativo
FOR EACH ROW
WHEN (NEW.estado = 'VIGENTE')
EXECUTE FUNCTION fn_versionar_elemento_normativo();

-- Prueba rápida

SELECT 
    trigger_name,
    event_manipulation,
    event_object_table,
    action_timing
FROM information_schema.triggers
WHERE event_object_table = 'elemento_normativo';

SELECT proname
FROM pg_proc
WHERE proname = 'fn_versionar_elemento_normativo';