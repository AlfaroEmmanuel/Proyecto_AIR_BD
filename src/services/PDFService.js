// =====================================================================
// src/services/PDFService.js — Issue #17 (extiende la base del Sprint 2 / #4)
// streamCertificacionAIR(res, opts):
//   - Forma RICA (#17):   { folio, hash, datos }   datos = obtener_datos_certificacion()
//   - Forma BÁSICA (S2):  { folio, hash, nombre, cedula, sector, periodo }
// Detecta `datos` para decidir qué renderizar (compatibilidad hacia atrás).
// =====================================================================
const PDFDocument = require('pdfkit');
const QRCode      = require('qrcode');

const BASE_URL = process.env.APP_URL || 'https://sistema-air.tec.ac.cr';

function fmt(f) { return f ? new Date(f).toLocaleDateString('es-CR') : ''; }

class PDFService {

    static async streamCertificacionAIR(res, opts) {
        const { folio, hash, datos } = opts;
        const doc = new PDFDocument({ size: 'LETTER', margin: 60 });
        res.setHeader('Content-Disposition', `inline; filename=Certificacion_${folio}.pdf`);
        res.setHeader('Content-Type', 'application/pdf');
        doc.pipe(res);

        // --- Encabezado (común) ---
        doc.fontSize(16).font('Helvetica-Bold')
           .text('ASAMBLEA INSTITUCIONAL REPRESENTATIVA', { align: 'center' });
        doc.fontSize(12).font('Helvetica')
           .text('Instituto Tecnológico de Costa Rica', { align: 'center' });
        doc.moveDown(0.5);
        doc.fontSize(14).font('Helvetica-Bold').text('CONSTANCIA', { align: 'center' });
        doc.fontSize(12).text(folio, { align: 'center' });
        doc.moveDown(1.5);

        if (datos) {
            await PDFService._cuerpoCompleto(doc, datos);
        } else {
            PDFService._cuerpoBasico(doc, opts);
        }

        // --- Firma (común) ---
        doc.moveDown(2);
        doc.font('Helvetica').fontSize(11);
        doc.text('_______________________________', { align: 'center' });
        doc.text('Presidencia del Directorio AIR', { align: 'center' });
        doc.moveDown(1.5);

        // --- Pie: folio + hash + QR (común) ---
        // Misma ruta que Certificado.construirUrlVerificacion (/verificar/).
        const urlValidacion = `${BASE_URL}/verificar/${folio}`;
        const qrImage = await QRCode.toDataURL(urlValidacion);
        doc.fontSize(9).font('Helvetica');
        const yPie = doc.y;
        doc.text(`Folio: ${folio}`, 60, yPie, { width: 380 });
        doc.text(`Hash SHA-256: ${hash}`, 60, doc.y, { width: 380 });
        doc.text(`Verificación: ${urlValidacion}`, 60, doc.y, { width: 380 });
        doc.image(qrImage, doc.page.width - 140, yPie - 6, { width: 80 });

        doc.end();
    }

    // --- Cuerpo completo (#17) ---
    static async _cuerpoCompleto(doc, datos) {
        const id = datos.identidad || {};
        doc.fontSize(11).font('Helvetica')
           .text('El Presidente del Directorio de la Asamblea Institucional Representativa hace constar que:', { align: 'justify' });
        doc.moveDown(0.6);
        doc.font('Helvetica-Bold').fontSize(12).text((id.nombre || '').toUpperCase(), { align: 'center' });
        doc.font('Helvetica').fontSize(11).text(`Cédula de identidad Nº ${id.cedula || ''}`, { align: 'center' });
        doc.moveDown();

        const seccion = (titulo) => { doc.moveDown(0.4); doc.font('Helvetica-Bold').fontSize(12).text(titulo); doc.font('Helvetica').fontSize(10); };

        seccion('Representación y vigencia');
        (datos.nombramientos || []).forEach(n =>
            doc.text(`• ${n.sector} — periodo ${n.periodo} (${fmt(n.fecha_inicio)} a ${n.fecha_fin ? fmt(n.fecha_fin) : 'vigente'})`));
        if (!(datos.nombramientos || []).length) doc.text('• Sin nombramientos en el periodo.');

        seccion('Asistencia');
        (datos.asistencia || []).forEach(t =>
            doc.text(`• ${t.tipo}: asistió a ${t.asistidas} de ${t.convocadas} sesiones (${t.porcentaje}%).`));
        if (!(datos.asistencia || []).length) doc.text('• No se registran sesiones convocadas en el periodo.');

        seccion('Comisiones');
        (datos.comisiones || []).forEach(c =>
            doc.text(`• ${c.comision} (desde ${fmt(c.fecha_ingreso)}${c.fecha_salida ? ' hasta ' + fmt(c.fecha_salida) : ''}) [${c.estado}]`));
        if (!(datos.comisiones || []).length) doc.text('• No integró comisiones en el periodo.');

        seccion('Propuestas');
        (datos.propuestas || []).forEach(p => {
            doc.text(`• ${p.titulo} — ${p.rol} [${p.estado}]`);
            if (p.leyenda_legal) { doc.fontSize(8).fillColor('#555').text(`   ${p.leyenda_legal}`, { align: 'justify' }); doc.fontSize(10).fillColor('#000'); }
        });
        if (!(datos.propuestas || []).length) doc.text('• No figura como proponente en el periodo.');

        doc.moveDown();
        doc.fontSize(10).font('Helvetica-Oblique').text(datos.clausula_301_lgap || '', { align: 'justify' });
        doc.font('Helvetica');
    }

    // --- Cuerpo básico (compatibilidad Sprint 2) ---
    static _cuerpoBasico(doc, { nombre, cedula, sector, periodo }) {
        doc.fontSize(11).font('Helvetica')
           .text('El Presidente del Directorio de la Asamblea Institucional Representativa hace constar que:', { align: 'justify' });
        doc.moveDown(0.8);
        doc.font('Helvetica-Bold').fontSize(12).text((nombre || '').toUpperCase(), { align: 'center' });
        doc.font('Helvetica').fontSize(11).text(`Cédula de identidad Nº ${cedula || ''}`, { align: 'center' });
        doc.moveDown();
        const cuerpo = `De acuerdo con los registros de la Secretaría de la AIR, la persona arriba identificada ${sector ? `asume la representación por el ${sector}` : 'forma parte del padrón institucional'}${periodo ? ` para el periodo ${periodo}` : ''} y su nombramiento se encuentra vigente.`;
        doc.text(cuerpo, { align: 'justify' });
        doc.moveDown();
        doc.fontSize(10).font('Helvetica-Oblique').text(
            'Se extiende la presente certificación con carácter de declaración jurada, al tenor del artículo 301 de la Ley General de la Administración Pública, consciente de las penas con las que la legislación castiga el falso testimonio.',
            { align: 'justify' });
        doc.font('Helvetica');
    }
}

module.exports = PDFService;
