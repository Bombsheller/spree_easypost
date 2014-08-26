Deface::Override.new(
  :name => "proper_display_of_order_shipments",
  :virtual_path => 'spree/admin/orders/_shipment',
  :insert_bottom => 'tr.show-tracking > td[colspan="5"]',
  :text => "<% if shipment.tracking.present? %>
              <%= link_to 'Get Shipping Label', shipping_label_admin_shipment_url(shipment.id), target: '_blank' %>
            <% end %>"
  )