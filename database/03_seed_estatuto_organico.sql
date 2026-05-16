-- =============================================
-- Issue #8: Carga Inicial del Estatuto Orgánico
-- Tablas oficiales: resolucion y elemento_normativo
-- =============================================

-- 1. Insertar resolución base para la carga inicial
INSERT INTO resolucion (
    folio_dair,
    fecha_aprobacion,
    descripcion  
)
VALUES (
    'DAIR-000-2026',
    CURRENT_DATE,
    'Carga inicial del Estatuto Orgánico institucional.'
)
ON CONFLICT (folio_dair) DO NOTHING;


-- 2. Insertar Título I
INSERT INTO elemento_normativo (
    id_padre,
    tipo,
    numero,
    texto_contenido,
    id_resolucion_origen,
    estado,
    orden
)
SELECT
    NULL,
    'TITULO',
    'I',
    'Título I: Disposiciones generales',
    r.id_resolucion,
    'VIGENTE',
    1
FROM resolucion r
WHERE r.folio_dair = 'DAIR-000-2026'
AND NOT EXISTS (
    SELECT 1
    FROM elemento_normativo e
    WHERE e.id_padre IS NULL
      AND e.tipo = 'TITULO'
      AND e.numero = 'I'
      AND e.estado = 'VIGENTE'
);


-- 3. Insertar Capítulo I como hijo del Título I
INSERT INTO elemento_normativo (
    id_padre,
    tipo,
    numero,
    texto_contenido,
    id_resolucion_origen,
    estado,
    orden
)
SELECT
    t.id_elemento,
    'CAPITULO',
    'I',
    'Capítulo I: Naturaleza y fines',
    r.id_resolucion,
    'VIGENTE',
    1
FROM elemento_normativo t
JOIN resolucion r
    ON r.folio_dair = 'DAIR-000-2026'
WHERE t.tipo = 'TITULO'
  AND t.numero = 'I'
  AND t.estado = 'VIGENTE'
  AND NOT EXISTS (
      SELECT 1
      FROM elemento_normativo e
      WHERE e.id_padre = t.id_elemento
        AND e.tipo = 'CAPITULO'
        AND e.numero = 'I'
        AND e.estado = 'VIGENTE'
  );


-- 4. Insertar Artículo 1 como hijo del Capítulo I
INSERT INTO elemento_normativo (
    id_padre,
    tipo,
    numero,
    texto_contenido,
    id_resolucion_origen,
    estado,
    orden
)
SELECT
    c.id_elemento,
    'ARTICULO',
    '1',
    'Artículo 1: Texto inicial del Estatuto Orgánico.',
    r.id_resolucion,
    'VIGENTE',
    1
FROM elemento_normativo c
JOIN resolucion r
    ON r.folio_dair = 'DAIR-000-2026'
WHERE c.tipo = 'CAPITULO'
  AND c.numero = 'I'
  AND c.estado = 'VIGENTE'
  AND NOT EXISTS (
      SELECT 1
      FROM elemento_normativo e
      WHERE e.id_padre = c.id_elemento
        AND e.tipo = 'ARTICULO'
        AND e.numero = '1'
        AND e.estado = 'VIGENTE'
  );


-- 5. Insertar Inciso a como hijo del Artículo 1
INSERT INTO elemento_normativo (
    id_padre,
    tipo,
    numero,
    texto_contenido,
    id_resolucion_origen,
    estado,
    orden
)
SELECT
    a.id_elemento,
    'INCISO',
    'a',
    'Inciso a): Texto inicial del inciso.',
    r.id_resolucion,
    'VIGENTE',
    1
FROM elemento_normativo a
JOIN resolucion r
    ON r.folio_dair = 'DAIR-000-2026'
WHERE a.tipo = 'ARTICULO'
  AND a.numero = '1'
  AND a.estado = 'VIGENTE'
  AND NOT EXISTS (
      SELECT 1
      FROM elemento_normativo e
      WHERE e.id_padre = a.id_elemento
        AND e.tipo = 'INCISO'
        AND e.numero = 'a'
        AND e.estado = 'VIGENTE'
  );

-- Prueba rápida
WITH RECURSIVE arbol_normativo AS (
    SELECT
        id_elemento,
        id_padre,
        tipo,
        numero,
        texto_contenido,
        estado,
        orden,
        1 AS nivel,
        numero::TEXT AS ruta
    FROM elemento_normativo
    WHERE id_padre IS NULL

    UNION ALL

    SELECT
        hijo.id_elemento,
        hijo.id_padre,
        hijo.tipo,
        hijo.numero,
        hijo.texto_contenido,
        hijo.estado,
        hijo.orden,
        padre.nivel + 1,
        padre.ruta || ' > ' || hijo.numero
    FROM elemento_normativo hijo
    JOIN arbol_normativo padre
        ON hijo.id_padre = padre.id_elemento
)
SELECT
    nivel,
    ruta,
    tipo,
    numero,
    texto_contenido,
    estado,
    orden
FROM arbol_normativo
ORDER BY ruta;

-- Prueba orden  
SELECT column_name
FROM information_schema.columns
WHERE table_name = 'elemento_normativo'
AND column_name = 'orden';

-- Actualización de registros
UPDATE elemento_normativo
SET orden = 1
WHERE tipo = 'TITULO'
  AND numero = 'I'
  AND estado = 'VIGENTE';

UPDATE elemento_normativo
SET orden = 1
WHERE tipo = 'CAPITULO'
  AND numero = 'I'
  AND estado = 'VIGENTE';

UPDATE elemento_normativo
SET orden = 1
WHERE tipo = 'ARTICULO'
  AND numero = '1'
  AND estado = 'VIGENTE';

UPDATE elemento_normativo
SET orden = 1
WHERE tipo = 'INCISO'
  AND numero = 'a'
  AND estado = 'VIGENTE';


-- datos de orden 
UPDATE elemento_normativo
SET orden = 1
WHERE estado = 'VIGENTE'
  AND orden IS NULL;