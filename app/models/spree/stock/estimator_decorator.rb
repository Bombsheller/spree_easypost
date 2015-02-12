Spree::Stock::Estimator.class_eval do
  # This method is overriden from the original in Spree::Stock::Estimator at line
  # 11. How much more complicated this method has become!
  # It's purpose is to return all possible shipping rates for the package passed
  # in the parameter. It works by informing EasyPost of all of the parameters
  # necessary for description of a package, that is shipper address, recipient
  # address, customs info, etc. as necessary.
  # Some complication occurs when EasyPost does not return any rates. This
  # has happened to us (team Bombsheller) when pathalogical international
  # addresses have been supplied by users. Because we only use FedEx to ship
  # internationally, when FedEx rejects that address, EasyPost has no rates to
  # offer us, and we're toast. To combat this, we fall back on Spree::ShippingMethod's
  # that live in the admin console. These describe how we shipped things before
  # EasyPost, so presumably we can use them again.
  def shipping_rates(package)
    order = package.order
    international_shipment = going_international?(package.stock_location, order.ship_address)

    easypost_rates = get_easypost_rates(package, order, international_shipment)

    if easypost_rates.any?

      easypost_rates.each do |rate|
        package.shipping_rates << Spree::ShippingRate.new(
          :name => "#{rate.carrier} #{rate.service.humanize}",
          :cost => rate.rate,
          :easy_post_shipment_id => rate.shipment_id,
          :easy_post_rate_id => rate.id
        )
      end
    else
      # Fall back to one of the shipping methods in the admin panel so we can at
      # least allow the customer to buy product.
      spree_shipping_rates = get_fallback_shipping_rates(international_shipment)
      package.shipping_rates = spree_shipping_rates
    end

    # If free shipping is enabled, present a price of 0 to the user.
    # EasyPost still charges whatever they normally would, though ;)
    # In Bombsheller's case, we don't want to foot the bill for international
    # shipments, so we don't make those have a cost of 0.
    if Spree::ShippingCategory.find_by_name('Free Shipping') && !international_shipment
      to_make_free = package.shipping_rates.first
      to_make_free.cost = 0
      to_make_free.save!
    end

    # Sets cheapest rate to be selected by default
    package.shipping_rates.first.selected = true

    package.shipping_rates
  end

  private

  def get_easypost_rates(package, order, international_shipment)
    from_address = build_easypost_address(package.stock_location)
    to_address = build_easypost_address(order.ship_address)

    parcel = build_easypost_parcel(package, international_shipment)

    shipment_info_hash = build_shipment_info_hash(from_address, to_address, parcel)

    shipment_info_hash[:customs_info] = build_customs_info(package) if international_shipment

    shipment = build_easypost_shipment(shipment_info_hash)

    rates = shipment.rates.sort_by { |r| r.rate.to_i }
  end

  def build_easypost_address(address)
    ep_address_attrs = {}
    # Stock locations do not have "company" attributes.
    ep_address_attrs[:company] = if address.respond_to?(:company)
      address.company
    else
      address.name
    end
    ep_address_attrs[:name] = address.full_name if address.respond_to?(:full_name)
    ep_address_attrs[:street1] = address.address1
    ep_address_attrs[:street2] = address.address2
    ep_address_attrs[:city] = address.city
    ep_address_attrs[:state] = address.state ? address.state.abbr : address.state_name
    ep_address_attrs[:zip] = address.zipcode
    ep_address_attrs[:country] = address.country.iso
    ep_address_attrs[:phone] = address.phone

    ::EasyPost::Address.create(ep_address_attrs)
  end

  def build_easypost_parcel(package, international_shipment)
    total_weight = package.contents.sum do |item|
      item.quantity * item.variant.weight
    end

    parcel_options = {:weight => total_weight}
    parcel_options[:predefined_package] = Spree::Config.preferred_international_packaging if international_shipment

    parcel = ::EasyPost::Parcel.create(parcel_options)
  end

  def going_international? from_address, to_address
    !(from_address.country.iso == to_address.country.iso)
  end

  # See https://www.easypost.com/customs-guide. In Bombsheller's case we only have one product,
  # so the customs info is stored in Spree settings. For others, the product or variant
  # is a better place for tariff number.
  def build_customs_info package
    customs_items = []
    line_items = package.contents.collect(&:line_item)
    value = line_items.sum do |item|
      item.variant.price * item.quantity
    end
    if Spree::Config.harmonized_tariff_number # Only shipping one product
      customs_items << EasyPost::CustomsItem.create(
        description: Spree::Config.item_customs_description,
        quantity: line_items.collect(&:quantity).inject(:+).to_i,
        value: value,
        weight: line_items.collect(&:variant).collect(&:weight).inject(:+).to_i,
        hs_tariff_number: Spree::Config.harmonized_tariff_number,
        origin_country: package.stock_location.country.iso)
    else
      # TODO: Group by tariff number and perform the above steps with each group.
    end

    customs_info = EasyPost::CustomsInfo.create(
      eel_pfc: package.order.ship_address.country.iso == 'CA' ? 'NOEEI 30.36' : 'NOEEI 30.37(a)',
      customs_certify: true,
      customs_signer: Spree::Config.customs_signer,
      contents_type: 'merchandise',
      customs_items: customs_items
      )
  end

  def build_shipment_info_hash(from_address, to_address, parcel)
    {
      :to_address => to_address,
      :from_address => from_address,
      :parcel => parcel
    }
  end

  def build_easypost_shipment(shipment_info_hash)
    shipment = ::EasyPost::Shipment.create(shipment_info_hash)
  end

  # Selects Spree::ShippingMethod's appropriately and generates Spree::ShippingRate's
  # from those.
  def get_fallback_shipping_rates(international_shipment)
    spree_shipping_methods = Spree::ShippingMethod.all
    if international_shipment
      # First filter to international shipping methods then to methods that use
      # preferred packaging, assuming preferred packaging has one word of method's
      # name in it, i.e. "FedExPak" contains "FedEx."
      international_methods = spree_shipping_methods.select { |m| m.name.match /international/i }
      packaging_name = Spree::Config.preferred_international_packaging
      methods = international_methods.select { |m| !m.name.split.select { |word| packaging_name.match word }.empty? }
      cost = 25
    else
      methods = spree_shipping_methods.select { |m| !m.name.match /international/i }
      cost = 10
    end
    methods.map { |method| Spree::ShippingRate.new(name: method.name, cost: cost, shipping_method: method) }
  end

end
