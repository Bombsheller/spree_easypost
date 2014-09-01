$(document).ready(function () {
    'use strict';

    var ship_button = $('[data-hook=admin_shipment_form] a.ship');

    ship_button.off('click');

    // handle ship click
    ship_button.on('click', function () {
      var link = $(this);
      var shipment_number = link.data('shipment-number');
      var url = Spree.url(Spree.routes.shipments_api + '/' + shipment_number + '/ship.json');
      $.ajax({
        type: 'PUT',
        url: url
      }).done(function () {
        window.location.reload();
      }).error(function (msg) {
        console.log('hola');
        console.log(msg);
        show_flash('error', msg.responseJSON.exception);
      });
    });
});