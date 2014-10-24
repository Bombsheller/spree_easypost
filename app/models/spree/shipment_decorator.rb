Spree::Shipment.class_eval do
  state_machine.before_transition :to => :shipped, :do => :buy_easypost_rate

  def tracking_url
    tracking_urls = {/USPS/i => "https://tools.usps.com/go/TrackConfirmAction.action?origTrackNum=",
                     /FedEx/i => "https://www.fedex.com/fedextrack/WTRK/index.html?action=track&trackingnumber=",
                     /UPS/i => "http://wwwapps.ups.com/WebTracking/track?track=yes&trackNums=",
                     /DHL/i => "http://webtrack.dhlglobalmail.com/?mobile=&trackingnumber="}
    shipping_method_name = self.selected_shipping_rate.name
    if shipping_method_name
      tracking_urls.each_pair do |key, value|
        return value + self.tracking if shipping_method_name.match(key)
      end
    end
  end

  def easypost_shipment
    @ep_shipment ||= EasyPost::Shipment.retrieve(selected_easy_post_shipment_id)
  end

  private

  def selected_easy_post_rate_id
    selected_shipping_rate.easy_post_rate_id
  end

  def selected_easy_post_shipment_id
    selected_shipping_rate.easy_post_shipment_id
  end

  # This method is run first thing when an admin user clicks the "SHIP" button
  # on a shipment. It works as follows:
  # 1) Check if a tracking number is already present for the package. If it is,
  #    we know the admin user has already bought a label and thus do not need
  #    one from EasyPost.
  # 2) If, during checkout, the store user selected a rate that EasyPost gave us,
  #    ask EasyPost to buy that rate. This has failed in the past for various
  #    reasons, primarily that FedEx hates us. If this step does not work for any
  #    reason, a flash message should appear on the admin console with a
  #    (hopefully) helpful message describing the error.
  #    If the user did not select an EasyPost rate (perhaps because none were
  #    available), no selected_easy_post_rate_id will be present, and the admin
  #    user will be notified appropriately, at which point s/he can buy a label
  #    and fill in tracking details by hand.
  # 3) If the selected EasyPost rate is successfully bought, get the tracking
  #    number from it and put it in the shipment's tracking field.
  def buy_easypost_rate
    if !self.tracking
      if selected_easy_post_rate_id
        rate = easypost_shipment.rates.find do |rate|
          rate.id == selected_easy_post_rate_id
        end

        logger.debug { "EasyPost shipping rate: #{rate}" }

        easypost_shipment.buy(rate)
        self.tracking = easypost_shipment.tracking_code
      else
        raise "This shipment has not been purchased with EasyPost. Please manually purchase label and fill in details."
      end
    end
  end
end