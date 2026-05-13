const pool = require('../../config/database');

// Lógica de procesamiento y control de roles
const login = async (req, res) => {
    const { usuario, contrasena, rol } = req.body;

    try {
        if (!usuario || !contrasena) {
            return res.status(400).json({ success: false, message: 'Usuario y contraseña requeridos.' });
        }

        // Validación base para el Sprint 2: Redirección condicional según rol
        let vistaDestino = '/consulta';
        if (rol === 'admin') vistaDestino = '/admin/dashboard';
        if (rol === 'secretaria') vistaDestino = '/secretaria/dashboard';

        return res.status(200).json({
            success: true,
            message: 'Autenticación exitosa',
            redirect: vistaDestino,
            userRole: rol
        });

    } catch (error) {
        return res.status(500).json({ success: false, message: 'Error interno del servidor.', error: error.message });
    }
};

module.exports = { login };
