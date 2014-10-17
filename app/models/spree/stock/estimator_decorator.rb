Spree::Stock::Estimator.class_eval do
  def shipping_rates(package)
    order = package.order

    from_address = process_address(package.stock_location)
    to_address = process_address(order.ship_address)

    international_shipment = going_international?(package.stock_location, order.ship_address)

    parcel = build_parcel(package, international_shipment)

    rates_with_preferred_packaging = get_rates_for_parcel_with_from_and_to_addresses(to_address, from_address, parcel, package, international_shipment)

    # This block handles the edge case of people putting in valid addresses but
    # getting no results due to preferred packaging. For example, if someone puts
    # in an international PO box and the preferred international packaging is
    # FedExPak, EasyPost will not return any USPS rates to respect the preferred
    # packaging, but FedEx doens't deliver to PO boxes, so the user won't be able
    # to receive the product! The solution is to try again, ignoring international
    # preferred packaging by passing in false to the build_parcel method while
    # keeping customs info intact by passing in international_shipment boolean to
    # the get_rates_for_parcel_with_from_and_to_addresses method.
    if rates_with_preferred_packaging.any?
      rates = rates_with_preferred_packaging
    else
      parcel = build_parcel(package, false)
      rates = get_rates_for_parcel_with_from_and_to_addresses(to_address, from_address, parcel, package, international_shipment)
    end

    if rates.any?

      rates.each do |rate|
        package.shipping_rates << Spree::ShippingRate.new(
          :name => "#{rate.carrier} #{rate.service}",
          :cost => rate.rate,
          :easy_post_shipment_id => rate.shipment_id,
          :easy_post_rate_id => rate.id
        )
      end

      # If free shipping is enabled, present a price of 0 to the user.
      # EasyPost still charges whatever they normally would, though ;)
      if Spree::ShippingCategory.find_by_name('Free Shipping')
        to_make_free = package.shipping_rates.first
        to_make_free.cost = 0
        to_make_free.save!
      end

      # Sets cheapest rate to be selected by default
      package.shipping_rates.first.selected = true

      package.shipping_rates
    else
      []
    end
  end

  private

  def get_rates_for_parcel_with_from_and_to_addresses(to_address, from_address, parcel, package, international_shipment)
    shipment_info_hash = build_shipment_info_hash(from_address, to_address, parcel)

    shipment_info_hash[:customs_info] = build_customs_info(package) if international_shipment

    shipment = build_shipment(shipment_info_hash)

    shipment.rates.sort_by { |r| r.rate.to_i }
  end

  def process_address(address)
    ep_address_attrs = {}
    # Stock locations do not have "company" attributes,
    ep_address_attrs[:company] = if address.respond_to?(:company)
      address.company
    else
      Spree::Config[:site_name]
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

  def build_parcel(package, international_shipment)
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
    if Spree::Config.harmonized_tariff_number # Only shipping one product
      customs_items << EasyPost::CustomsItem.create(
        description: Spree::Config.item_customs_description,
        quantity: line_items.collect(&:quantity).inject(:+).to_i,
        value: line_items.collect(&:variant).collect(&:price).inject(:+).to_i,
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

  def build_shipment(shipment_info_hash)
    shipment = ::EasyPost::Shipment.create(shipment_info_hash)
  end

end
