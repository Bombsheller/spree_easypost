module Spree
  module Admin
    class ShipmentsController < ResourceController
      # A handy helper to make getting shipping labels easier. The admin user
      # never has to go to EasyPost's site to get the shipping label.
      def shipping_label
        spree_shipment = Spree::Shipment.find(params[:id])
        logger.debug { "Spree::Shipment: #{spree_shipment}" }
        logger.debug { "EasyPost::Shipment: #{spree_shipment.easypost_shipment}" }
        postage_label_url = spree_shipment.easypost_shipment.postage_label["label_url"]
        if postage_label_url
          redirect_to postage_label_url
        else
          flash[:error] = "An error occurred getting the shipping label. Please login to EasyPost and download from there."
        redirect_to edit_admin_order_path(spree_shipment.order)
        end
      end
    end
  end
end