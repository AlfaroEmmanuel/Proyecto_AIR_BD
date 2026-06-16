// =====================================================================
// src/routes/api.js — Definición de rutas REST
// =====================================================================
const express = require('express');
const router  = express.Router();

const AuthController         = require('../controllers/AuthController');
const AsambleistaController  = require('../controllers/AsambleistaController');
const FolioController        = require('../controllers/FolioController');
const SesionController      = require('../controllers/SesionController');
const PropuestaController   = require('../controllers/PropuestaController');
const AsistenciaController  = require('../controllers/AsistenciaController');
const ComisionController    = require('../controllers/ComisionController');
const ReportesController = require('../controllers/ReportesController');
const CertificadoController = require('../controllers/CertificadoController');
const AnulacionController   = require('../controllers/AnulacionController');
const CatalogoController    = require('../controllers/CatalogoController');
const { requireAuth, requireRole } = AuthController;


// ---------------------------------------------------------------------
// Catálogos de apoyo para la UI (periodos de gestión, sectores)
// ---------------------------------------------------------------------
router.get('/catalogos/periodos',
    requireAuth,
    CatalogoController.periodos
);
router.get('/catalogos/sectores',
    requireAuth,
    CatalogoController.sectores
);


// ---------------------------------------------------------------------
// Issue #0 — Autenticación
// ---------------------------------------------------------------------
router.post('/login', AuthController.login);

// ---------------------------------------------------------------------
// Issue #1 — Folios
// ---------------------------------------------------------------------
router.get('/folio/nuevo',
    requireAuth, requireRole('Secretaria','Administrador'),
    FolioController.obtenerSiguiente
);
router.get('/folio/anio/:anio',
    requireAuth,
    FolioController.consultarPorAnio
);

// ---------------------------------------------------------------------
// Issues #3, #9 — Asambleístas
// ---------------------------------------------------------------------
router.get ('/asambleistas',
    requireAuth,
    AsambleistaController.listar
);
router.get ('/asambleistas/buscar',
    requireAuth,
    AsambleistaController.buscar
);
router.post('/asambleistas',
    requireAuth, requireRole('Secretaria','Administrador'),
    AsambleistaController.registrar
);

// Issue #2 — Hoja de vida (trazabilidad de identidad y nombramientos)
router.get('/asambleistas/:cedula/hoja-vida',
    requireAuth, requireRole('Secretaria','Administrador'),
    AsambleistaController.hojaDeVida
);

// ---------------------------------------------------------------------
// Issue #11 — Sesiones y Votaciones
// ---------------------------------------------------------------------
router.get ('/sesiones',
    requireAuth, SesionController.listar);
router.post('/sesiones',
    requireAuth, requireRole('Secretaria','Administrador'), SesionController.crear);
router.get ('/sesiones/:id',
    requireAuth, SesionController.obtenerDetalle);
router.post('/sesiones/:id/votacion',
    requireAuth, requireRole('Secretaria','Administrador'), SesionController.registrarVotacion);

// Propuestas (#11) + leyenda legal (#5)
router.post('/propuestas',
    requireAuth, requireRole('Secretaria','Administrador'), PropuestaController.crear);
router.get ('/propuestas/:id_propuesta/leyenda',
    requireAuth, PropuestaController.obtenerLeyendaLegal);   // consumido por #17

// ---------------------------------------------------------------------
// Issue #12 — Asistencias
// ---------------------------------------------------------------------
router.get ('/asistencias/padron-vigente',
    requireAuth, AsistenciaController.obtenerPadronVigente);
router.post('/asistencias/sesion/:id_sesion',
    requireAuth, requireRole('Secretaria','Administrador'), AsistenciaController.registrarAsistenciaSesion);
router.get ('/asistencias/asambleista/:cedula',
    requireAuth, AsistenciaController.obtenerAsistenciasAsambleista);
router.get ('/asistencias/asambleista/:cedula/porcentaje',
    requireAuth, AsistenciaController.calcularPorcentaje);

// ---------------------------------------------------------------------
// Issue #6 — Comisiones
// ---------------------------------------------------------------------
router.get ('/comisiones',
    requireAuth, ComisionController.listar);
router.get ('/comisiones/:id_comision',
    requireAuth, ComisionController.obtenerDetalle);
router.post('/comisiones',
    requireAuth, requireRole('Secretaria','Administrador'), ComisionController.crear);
router.post('/comisiones/:id_comision/integrantes',
    requireAuth, requireRole('Secretaria','Administrador'), ComisionController.agregarIntegrantes);

// ---------------------------------------------------------------------
// Issues #7 / Ext #8 — Reporte de asistencia consolidada
// ---------------------------------------------------------------------
router.get('/reportes/asistencia/:cedula',
    requireAuth, ReportesController.asistenciaAsambleista);

// ---------------------------------------------------------------------
// Issue #16 — Reportería administrativa (JSON o ?formato=csv)
// ---------------------------------------------------------------------
router.get('/reportes/kpis',
    requireAuth, requireRole('Secretaria','Administrador'), ReportesController.kpis);
router.get('/reportes/certificaciones-mensuales',
    requireAuth, requireRole('Secretaria','Administrador'), ReportesController.certificacionesMensuales);
router.get('/reportes/asambleistas-mas-certificados',
    requireAuth, requireRole('Secretaria','Administrador'), ReportesController.asambleistasMasCertificados);
router.get('/reportes/distribucion-sectores',
    requireAuth, requireRole('Secretaria','Administrador'), ReportesController.distribucionSectores);

// ---- #13 — Historial global de certificaciones ----
router.get('/reportes/certificaciones-historial',
    requireAuth, requireRole('Secretaria','Administrador'), ReportesController.historialCertificaciones);

// ---------------------------------------------------------------------
// Issue #17 — MOTOR: genera y devuelve el PDF inline
// (Única ruta de generación: usa el motor completo, no el básico del Sprint 2)
// ---------------------------------------------------------------------
router.post('/certificacion/generar',
    requireAuth, requireRole('Secretaria','Administrador'),
    CertificadoController.generarCertificacionPDF);

// ---------------------------------------------------------------------
// Issue #14 — Emisión y Verificación
// ---------------------------------------------------------------------
router.post('/certificaciones/emitir',
    requireAuth, requireRole('Secretaria','Administrador'), CertificadoController.emitir);

// PÚBLICAS (sin auth) — usadas por terceros y por el QR del PDF
router.get ('/certificaciones/verificar/:folio', CertificadoController.verificar);
router.post('/certificaciones/verificar/hash',   CertificadoController.verificarHash);

router.get ('/certificaciones/historial/:cedula',
    requireAuth, requireRole('Secretaria','Administrador'), CertificadoController.historial);

// ---------------------------------------------------------------------
// Issue #15 — Anulaciones y Sustituciones (solo Administrador)
// ---------------------------------------------------------------------
router.post('/anulaciones/anular',
    requireAuth, requireRole('Administrador'), AnulacionController.anular);
router.post('/anulaciones/sustituir',
    requireAuth, requireRole('Administrador'), AnulacionController.sustituir);
router.get ('/anulaciones/historial',
    requireAuth, requireRole('Administrador'), AnulacionController.historial);
router.get ('/anulaciones/historial/:folio',
    requireAuth, requireRole('Administrador'), AnulacionController.historialPorFolio);
router.get ('/anulaciones/estado/:folio',
    requireAuth, requireRole('Secretaria','Administrador'), AnulacionController.estado);

module.exports = router;
