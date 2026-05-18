const pool = require('../../config/database');

const obtenerSiguienteFolio = async (req, res) => {
    try {
        // Llama a la función SQL que creamos antes
        const result = await pool.query('SELECT generar_siguiente_folio() AS folio');
        res.json({ exito: true, folio: result.rows[0].folio });
    } catch (error) {
        console.error('Error generando folio:', error);
        res.status(500).json({ exito: false, mensaje: 'Error al generar folio' });
    }
};

module.exports = { obtenerSiguienteFolio };
