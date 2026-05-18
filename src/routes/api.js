const express = require('express');
const router = express.Router();

// Importar los controladores
const { login } = require('../controllers/autentificador_controller');
const { obtenerSiguienteFolio } = require('../controllers/folio_controller');
const { generarCertificacionPDF } = require('../controllers/certificacion_controller');
const Asambleista = require('../models/Asambleista');

// Issue #0: Login
router.post('/login', login);

// Issue #1: Folio
router.get('/folio/nuevo', obtenerSiguienteFolio);

// Issue #3: Buscador Avanzado
router.post('/asambleistas/buscar', async (req, res) => {
    const resultados = await Asambleista.buscarAvanzado(req.body);
    res.json(resultados);
});

// Issue #4 y #14: Generar PDF con QR
router.post('/certificacion/generar', generarCertificacionPDF);

module.exports = router;
