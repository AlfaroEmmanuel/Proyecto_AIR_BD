const pool = require('../../config/database');


// ISSUE #2: REGISTRO DE ASAMBLEÍSTAS Y NOMBRAMIENTOS

const registrarAsambleista = async (req, res) => {
    const { cedula, nombre, primer_apellido, segundo_apellido, correo, id_sector, id_periodo } = req.body;

    try {
        
        await pool.query('BEGIN');

      
        const queryAsambleista = `
            INSERT INTO asambleista (cedula, nombre, primer_apellido, segundo_apellido, correo_institucional)
            VALUES ($1, $2, $3, $4, $5)
            ON CONFLICT (cedula) DO UPDATE SET
                nombre = $2, primer_apellido = $3, segundo_apellido = $4, correo_institucional = $5;
        `;
        await pool.query(queryAsambleista, [cedula, nombre, primer_apellido, segundo_apellido, correo]);

        // 2. Insertar el Nombramiento Temporal ligado a un periodo específico
       
        const queryNombramiento = `
            INSERT INTO nombramiento (cedula_asambleista, id_sector, id_periodo)
            VALUES ($1, $2, $3);
        `;
        await pool.query(queryNombramiento, [cedula, id_sector, id_periodo]);

        await pool.query('COMMIT'); // Guardado seguro en DB
        return res.status(201).json({ success: true, message: 'Asambleísta y Periodo registrados de manera exitosa.' });

    } catch (error) {
        await pool.query('ROLLBACK'); // Deshace los cambios si algo falló o si el trigger saltó
        return res.status(500).json({ success: false, message: 'Error al procesar el registro.', error: error.message });
    }
};


// ISSUE #3: BÚSQUEDA Y LISTADO HISTÓRICO

const buscarYListarAsambleistas = async (req, res) => {
    const { cedula } = req.query;

    try {
        // Query relacional base uniendo las identidades con sus nombramientos temporales
        let queryText = `
            SELECT a.cedula, a.nombre, a.primer_apellido, a.segundo_apellido, a.correo_institucional,
                   s.nombre_sector, p.anio_gestion, n.estado_activo, n.fecha_nombramiento
            FROM asambleista a
            INNER JOIN nombramiento n ON a.cedula = n.cedula_asambleista
            INNER JOIN sector s ON n.id_sector = s.id_sector
            INNER JOIN periodo_gestion p ON n.id_periodo = p.id_periodo
        `;
        
        const params = [];
        
        // Filtro por cédula si el usuario digita en el buscador
        if (cedula) {
            queryText += ` WHERE a.cedula = $1`;
            params.push(cedula);
        }

        queryText += ` ORDER BY p.anio_gestion DESC, a.primer_apellido ASC;`;

        const result = await pool.query(queryText, params);
        return res.status(200).json(result.rows);

    } catch (error) {
        return res.status(500).json({ success: false, message: 'Error en la consulta de base de datos.', error: error.message });
    }
};

module.exports = { registrarAsambleista, buscarYListarAsambleistas };
