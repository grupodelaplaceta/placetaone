/*
 * Placeta One · Pasarela para webs de bancos (navegador, sin dependencias).
 * Uso: incluir este script y llamar a PlacetaCheckout.abrir(...) desde un clic del usuario
 * (los navegadores bloquean ventanas que no vienen de un clic).
 *
 *   PlacetaCheckout.abrir({
 *     url: respuestaDeTuBackend.url,          // url que devuelve POST /api/v1/bk/checkouts
 *     onPagado: function (r) { ... },          // r.transaccion
 *     onError: function (r) { ... },           // cancelado, caducado, fallido o popup bloqueado
 *   });
 */
(function () {
  var ORIGEN_PLACETA = "https://placetaone.vercel.app";
  var TIPO = "placeta.checkout";

  window.PlacetaCheckout = {
    configurar: function (o) { if (o && o.origen) ORIGEN_PLACETA = o.origen; },
    abrir: function (o) {
      var ancho = 440, alto = 640;
      var izq = Math.max(0, (window.screenX || 0) + ((window.outerWidth || ancho) - ancho) / 2);
      var arr = Math.max(0, (window.screenY || 0) + ((window.outerHeight || alto) - alto) / 2);
      var ventana = window.open(o.url, "placeta_checkout",
        "width=" + ancho + ",height=" + alto + ",left=" + izq + ",top=" + arr + ",noopener=no");
      if (!ventana) { if (o.onError) o.onError({ estado: "popup_bloqueado" }); return; }
      function escuchar(e) {
        if (e.origin !== ORIGEN_PLACETA) return;               // solo mensajes de Placeta
        if (!e.data || e.data.tipo !== TIPO) return;
        window.removeEventListener("message", escuchar);
        if (e.data.estado === "pagado") { if (o.onPagado) o.onPagado(e.data); }
        else { if (o.onError) o.onError(e.data); }
      }
      window.addEventListener("message", escuchar);
    }
  };
})();
