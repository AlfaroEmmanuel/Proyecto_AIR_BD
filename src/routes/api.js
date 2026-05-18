// =====================================================================
// src/routes/api.js — Definición de rutas REST
// =====================================================================
const express = require('express');
const router  = express.Router();

const AuthController         = require('../controllers/AuthController');
const AsambleistaController  = require('../controllers/AsambleistaController');
const FolioController        = require('../controllers/FolioController');
const CertificacionController= require('../controllers/CertificacionController');

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

module.exports = router;
