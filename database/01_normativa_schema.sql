-- =============================================
-- Issue #6: Modelo de Datos Normativo Recursivo
-- Ajustes sobre la tabla existente elemento_normativo
-- =============================================

-- La tabla elemento_normativo ya existe en script_inicial_AIR.sql.
-- Su relación recursiva se implementa mediante:
-- id_padre REFERENCES elemento_normativo(id_elemento)

-- Se agrega el campo orden para preservar la posición del elemento
-- dentro de su padre normativo.
ALTER TABLE elemento_normativo
ADD COLUMN IF NOT EXISTS orden INT;

-- Restricción para asegurar que el orden sea positivo.
ALTER TABLE elemento_normativo
ADD CONSTRAINT chk_elemento_normativo_orden
CHECK (orden IS NULL OR orden > 0);

-- Comentarios documentales del modelo recursivo.
COMMENT ON TABLE elemento_normativo IS
'Tabla recursiva para representar la jerarquía normativa: Título > Capítulo > Artículo > Inciso.';

COMMENT ON COLUMN elemento_normativo.id_padre IS
'Referencia recursiva al elemento normativo padre. Permite construir jerarquías normativas.';

COMMENT ON COLUMN elemento_normativo.orden IS
'Orden del elemento dentro de su padre normativo.';