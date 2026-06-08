// =====================================================================
// src/services/CSVService.js — Issue #16
// Conversión de filas a CSV sin dependencias externas. Maneja comas,
// comillas, saltos de línea y BOM para que Excel respete los acentos.
// =====================================================================

class CSVService {

    static escaparCelda(valor) {
        if (valor === null || valor === undefined) return '';
        const texto = String(valor);
        if (/[",\n\r]/.test(texto)) {
            return '"' + texto.replace(/"/g, '""') + '"';
        }
        return texto;
    }

    static generar(filas, columnas) {
        if (!Array.isArray(filas)) throw new Error('CSVService: "filas" debe ser un array.');
        const cols = (columnas && columnas.length)
            ? columnas
            : (filas.length ? Object.keys(filas[0]) : []);
        const encabezado = cols.map(CSVService.escaparCelda).join(',');
        const cuerpo = filas
            .map((fila) => cols.map((c) => CSVService.escaparCelda(fila[c])).join(','))
            .join('\r\n');
        const BOM = '\uFEFF';
        return BOM + encabezado + '\r\n' + cuerpo;
    }

    static enviarComoDescarga(res, nombreArchivo, filas, columnas) {
        const csv = CSVService.generar(filas, columnas);
        res.setHeader('Content-Type', 'text/csv; charset=utf-8');
        res.setHeader('Content-Disposition', `attachment; filename="${nombreArchivo}"`);
        res.status(200).send(csv);
    }
}

module.exports = CSVService;
