// =====================================================================
// src/services/PDFService.js — Generación de PDF de certificación
// Issue #4: Visualización formal — Plantilla oficial AIR
// =====================================================================
const PDFDocument = require('pdfkit');
const QRCode      = require('qrcode');

class PDFService {

    /**
     * Renderiza el PDF de certificación directamente al stream de respuesta HTTP.
     * Sigue el formato oficial descrito en la documentación de la AIR:
     *  - Encabezado institucional
     *  - Acreditación de autoridad
     *  - Cuerpo de participaciones
     *  - Cláusula art. 301 LGAP
     *  - Folio + Hash + QR
     */
    static async streamCertificacionAIR(res, { folio, hash, nombre, cedula, sector, periodo }) {
        const doc = new PDFDocument({ size: 'LETTER', margin: 60 });

        res.setHeader('Content-Disposition', `inline; filename=Certificacion_${folio}.pdf`);
        res.setHeader('Content-Type', 'application/pdf');
        doc.pipe(res);

        // --- Encabezado
        doc.fontSize(16).font('Helvetica-Bold')
           .text('ASAMBLEA INSTITUCIONAL REPRESENTATIVA', { align: 'center' });
        doc.fontSize(12).font('Helvetica')
           .text('Instituto Tecnológico de Costa Rica', { align: 'center' });
        doc.moveDown(0.5);
        doc.fontSize(14).font('Helvetica-Bold')
           .text('CONSTANCIA', { align: 'center' });
        doc.fontSize(12).text(folio, { align: 'center' });
        doc.moveDown(1.5);

        // --- Acreditación de autoridad
        doc.fontSize(11).font('Helvetica')
           .text('El Presidente del Directorio de la Asamblea Institucional Representativa hace constar que:',
                 { align: 'justify' });
        doc.moveDown(0.8);
        doc.font('Helvetica-Bold').fontSize(12).text(nombre.toUpperCase(), { align: 'center' });
        doc.font('Helvetica').fontSize(11).text(`Cédula de identidad Nº ${cedula}`, { align: 'center' });
        doc.moveDown();

        // --- Cuerpo
        const cuerpo = `De acuerdo con los registros de la Secretaría de la AIR, la persona arriba identificada ${sector ? `asume la representación por el ${sector}` : 'forma parte del padrón institucional'}${periodo ? ` para el periodo ${periodo}` : ''} y su nombramiento se encuentra vigente.`;
        doc.text(cuerpo, { align: 'justify' });
        doc.moveDown();

        // --- Cláusula legal (art. 301 LGAP)
        doc.fontSize(10).font('Helvetica-Oblique')
           .text(
               'Se extiende la presente certificación con carácter de declaración jurada, ' +
               'al tenor del artículo 301 de la Ley General de la Administración Pública, ' +
               'consciente de las penas con las que la legislación castiga el falso testimonio.',
               { align: 'justify' }
           );
        doc.moveDown(2);

        // --- Firma
        doc.font('Helvetica').fontSize(11);
        doc.text('_______________________________', { align: 'center' });
        doc.text('Presidencia del Directorio AIR',   { align: 'center' });
        doc.moveDown(2);

        // --- Folio + Hash + QR
        const urlValidacion = `https://sistema-air.tec.ac.cr/validar/${folio}`;
        const qrImage = await QRCode.toDataURL(urlValidacion);

        doc.fontSize(9).font('Helvetica');
        doc.text(`Folio: ${folio}`,  { align: 'left' });
        doc.text(`Hash SHA-256: ${hash}`, { align: 'left' });
        doc.text(`Verificación: ${urlValidacion}`, { align: 'left' });

        const qrX = doc.page.width - 140;
        const qrY = doc.y - 50;
        doc.image(qrImage, qrX, qrY, { width: 80 });

        doc.end();
    }
}

module.exports = PDFService;
