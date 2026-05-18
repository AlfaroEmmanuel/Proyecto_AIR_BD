const PDFDocument = require('pdfkit');
const QRCode = require('qrcode');

const generarCertificacionPDF = async (req, res) => {
    try {
        const { nombre, cedula, folio } = req.body; // Datos que vienen del frontend

        // 1. Crear el documento PDF
        const doc = new PDFDocument({ margin: 50 });
        
        // Configurar la respuesta como un archivo PDF para el navegador
        res.setHeader('Content-disposition', `inline; filename=Certificacion_${cedula}.pdf`);
        res.setHeader('Content-type', 'application/pdf');
        doc.pipe(res);

        // 2. Generar el Código QR (Validación Issue #14)
        // El QR contendrá un hash ficticio o URL de validación
        const urlValidacion = `https://sistema-air.tec.ac.cr/validar/${folio}`;
        const qrImage = await QRCode.toDataURL(urlValidacion);

        // 3. Dibujar el PDF (Issue #4)
        doc.fontSize(20).text('Asamblea Institucional Representativa', { align: 'center' });
        doc.moveDown();
        doc.fontSize(14).text(`Folio de Control: ${folio}`, { align: 'right' });
        doc.moveDown();
        doc.fontSize(12).text(`Por medio de la presente se certifica que el asambleísta ${nombre} con cédula ${cedula} se encuentra activo en sus funciones.`, { align: 'justify' });
        
        doc.moveDown(4);
        doc.image(qrImage, doc.page.width / 2 - 50, doc.y, { width: 100 });
        doc.text('Escanear para validar autenticidad', { align: 'center' });

        doc.end();

    } catch (error) {
        console.error('Error generando PDF:', error);
        res.status(500).send('Error interno generando el documento');
    }
};

module.exports = { generarCertificacionPDF };
