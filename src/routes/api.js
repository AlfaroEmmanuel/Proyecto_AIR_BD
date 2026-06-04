// =====================================================================
// src/routes/api.js — Definición de rutas REST
// =====================================================================
const express = require('express');
const router  = express.Router();

const AuthController         = require('../controllers/AuthController');
const AsambleistaController  = require('../controllers/AsambleistaController');
const FolioController        = require('../controllers/FolioController');
const CertificacionController= require('../controllers/CertificacionController');
const SesionController      = require('../controllers/SesionController');
const PropuestaController   = require('../controllers/PropuestaController');
const AsistenciaController  = require('../controllers/AsistenciaController');
const ComisionController    = require('../controllers/ComisionController');
const { requireAuth, requireRole } = AuthController;

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
// Issues #4, #14 — Certificaciones (PDF + QR + Hash)
// ---------------------------------------------------------------------
router.post('/certificacion/generar',
    requireAuth, requireRole('Secretaria','Administrador'),
    CertificacionController.generarCertificacionPDF
);
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
    requireAuth, PropuestaController.obtenerLeyendaLegal);   // consumido por #17 (Persona C)

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

module.exports = router;
