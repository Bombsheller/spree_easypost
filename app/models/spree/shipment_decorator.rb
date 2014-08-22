Spree::Shipment.class_eval do
  state_machine.before_transition :to => :shipped, :do => :buy_easypost_rate
  class_variable_set(:@@tracking_urls,
                      {/USPS/i => "https://tools.usps.com/go/TrackConfirmAction.action?origTrackNum=",
                       /FedEx/i => "https://www.fedex.com/fedextrack/WTRK/index.html?action=track&trackingnumber=",
                       /UPS/i => "http://wwwapps.ups.com/WebTracking/track?track=yes&trackNums=",
                       /DHL/i => "http://webtrack.dhlglobalmail.com/?mobile=&trackingnumber="}
                    )

  def tracking_url
    shipping_method_name = self.selected_shipping_rate.name
    if shipping_method_name
      @@tracking_urls.each_pair do |key, value|
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

  def buy_easypost_rate
    rate = easypost_shipment.rates.find do |rate|
      rate.id == selected_easy_post_rate_id
    end

    easypost_shipment.buy(rate)
    self.tracking = easypost_shipment.tracking_code
  end
end