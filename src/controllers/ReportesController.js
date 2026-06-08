// =====================================================================
// src/controllers/ReportesController.js — Issues #7, Ext #8, #16, historial #13
// =====================================================================
const Reporte = require('../models/Reporte');
const CSVService = require('../services/CSVService');

// ---- #7 / Ext #8 — Asistencia ----
const asistenciaAsambleista = async (req, res) => {
    try {
        const { cedula } = req.params;
        const desde = req.query.desde || '1900-01-01';
        const hasta = req.query.hasta || new Date().toISOString().slice(0, 10);
        const datos = await Reporte.asistenciaAsambleista(cedula, desde, hasta);
        return res.json({ exito: true, datos: { cedula, desde, hasta, asistencia: datos } });
    } catch (error) {
        console.error('[ReportesController.asistenciaAsambleista]', error);
        return res.status(500).json({ exito: false, mensaje: 'Error al calcular la asistencia.' });
    }
};

// ---- #16 — Reportería (JSON o ?formato=csv) ----
const certificacionesMensuales = async (req, res) => {
    try {
        const anio = Number(req.query.anio) || new Date().getFullYear();
        const filas = await Reporte.certificacionesPorMes(anio);
        if (req.query.formato === 'csv') {
            return CSVService.enviarComoDescarga(res, `certificaciones-${anio}.csv`, filas, ['anio', 'mes', 'total']);
        }
        return res.json({ exito: true, datos: filas });
    } catch (error) {
        console.error('[ReportesController.certificacionesMensuales]', error);
        return res.status(500).json({ exito: false, mensaje: 'Error al generar el reporte.' });
    }
};

const asambleistasMasCertificados = async (req, res) => {
    try {
        const filas = await Reporte.asambleistasMasCertificados(Number(req.query.limite) || 20);
        if (req.query.formato === 'csv') {
            return CSVService.enviarComoDescarga(res, 'asambleistas-mas-certificados.csv', filas,
                ['cedula', 'nombre', 'total_certificaciones']);
        }
        return res.json({ exito: true, datos: filas });
    } catch (error) {
        console.error('[ReportesController.asambleistasMasCertificados]', error);
        return res.status(500).json({ exito: false, mensaje: 'Error al generar el reporte.' });
    }
};

const distribucionSectores = async (req, res) => {
    try {
        const filas = await Reporte.distribucionSectores();
        if (req.query.formato === 'csv') {
            return CSVService.enviarComoDescarga(res, 'distribucion-sectores.csv', filas,
                ['sector', 'total_asambleistas', 'porcentaje']);
        }
        return res.json({ exito: true, datos: filas });
    } catch (error) {
        console.error('[ReportesController.distribucionSectores]', error);
        return res.status(500).json({ exito: false, mensaje: 'Error al generar el reporte.' });
    }
};

const kpis = async (req, res) => {
    try {
        const anio = Number(req.query.anio) || new Date().getFullYear();
        const data = await Reporte.kpis(anio);
        return res.json({ exito: true, datos: { anio, ...data } });
    } catch (error) {
        console.error('[ReportesController.kpis]', error);
        return res.status(500).json({ exito: false, mensaje: 'Error al obtener los KPIs.' });
    }
};

// ---- #13 — Historial global de certificaciones ----
const historialCertificaciones = async (req, res) => {
    try {
        const { desde, hasta, idUsuario } = req.query;
        const datos = await Reporte.historialCertificaciones({
            desde, hasta, idUsuario: idUsuario ? Number(idUsuario) : undefined
        });
        return res.json({ exito: true, datos });
    } catch (error) {
        console.error('[ReportesController.historialCertificaciones]', error);
        return res.status(500).json({ exito: false, mensaje: 'Error al obtener el historial.' });
    }
};

module.exports = {
    asistenciaAsambleista,
    certificacionesMensuales,
    asambleistasMasCertificados,
    distribucionSectores,
    kpis,
    historialCertificaciones
};
