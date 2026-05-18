const Usuario = require('../models/Usuario');

const login = async (req, res) => {
    try {
        const { username, password } = req.body;
        
        // Validación real en el Modelo
        const usuario = await Usuario.encontrarPorCredenciales(username, password);
        
        if (!usuario) {
            return res.status(401).json({ exito: false, mensaje: 'Credenciales inválidas.' });
        }

        // Devolvemos el rol real guardado seguro en la BD
        return res.json({
            exito: true,
            rol: usuario.nombre_rol,
            redireccion: usuario.nombre_rol === 'Secretaría' ? '/registro_asambleista.view.html' : '/listado_asambleistas.html'
        });

    } catch (error) {
        console.error(error);
        res.status(500).json({ exito: false, mensaje: 'Error interno del servidor.' });
    }
};

module.exports = { login };
