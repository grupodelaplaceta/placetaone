const { chromium } = require('/home/claude/.npm-global/lib/node_modules/playwright');
const [,, src, out] = process.argv;
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1243/chrome-linux64/chrome', args: ['--no-sandbox'] });
  const p = await b.newPage();
  await p.goto('file://' + src, { waitUntil: 'load' });
  await p.pdf({ path: out, format: 'A4', printBackground: true,
    margin: { top: '18mm', bottom: '18mm', left: '15mm', right: '15mm' },
    displayHeaderFooter: true, headerTemplate: '<span></span>',
    footerTemplate: '<div style="font-size:8px;width:100%;text-align:center;color:#888;font-family:Arial">Placeta One · Guía de uso · página <span class="pageNumber"></span> de <span class="totalPages"></span></div>' });
  await b.close();
  console.log('PDF generado:', out);
})().catch(e => { console.error('ERROR', e.message); process.exit(1); });
