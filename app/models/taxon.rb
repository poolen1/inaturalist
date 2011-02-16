class Taxon < ActiveRecord::Base
  # Sometimes you don't want to make a new taxon name with a taxon, like when
  # you're saving a new taxon name with a new associated taxon. Hence, this.
  attr_accessor :skip_new_taxon_name
  
  # If you want to shove some HTML in there before creating some JSON...
  attr_accessor :html
  
  acts_as_flaggable
  has_ancestry
  
  has_many :child_taxa, :class_name => Taxon.to_s, :foreign_key => :parent_id
  has_many :taxon_names, :dependent => :destroy
  has_many :observations, :dependent => :nullify
  has_many :listed_taxa, :dependent => :destroy
  has_many :lists, :through => :listed_taxa
  has_many :places, :through => :listed_taxa
  has_many :identifications, :dependent => :destroy
  has_many :taxon_links, :dependent => :destroy 
  has_many :taxon_ranges, :dependent => :destroy
  has_many :taxon_photos, :dependent => :destroy
  has_many :photos, :through => :taxon_photos
  belongs_to :source
  belongs_to :iconic_taxon, :class_name => 'Taxon', :foreign_key => 'iconic_taxon_id'
  belongs_to :creator, :class_name => 'User'
  belongs_to :updater, :class_name => 'User'
  has_and_belongs_to_many :colors
  
  define_index do
    indexes :name
    indexes taxon_names.name, :as => :names
    indexes colors.value, :as => :color_values
    has iconic_taxon_id, :facet => true, :type => :integer
    has colors(:id), :as => :colors, :facet => true, :type => :multi
    has listed_taxa(:place_id), :as => :places, :facet => true, :type => :multi
    has listed_taxa(:list_id), :as => :lists, :type => :multi
    has created_at, ancestry
    has "REPLACE(ancestry, '/', ',')", :as => :ancestors, :type => :multi
    set_property :delta => :delayed
  end
  
  before_validation :normalize_rank, :set_rank_level, :remove_rank_from_name
  before_save :set_iconic_taxon, # if after, it would require an extra save
              :capitalize_name
  after_save :create_matching_taxon_name,
             :set_wikipedia_summary_later,
             :handle_after_move
  
  validates_presence_of :name, :rank
  validates_uniqueness_of :name, 
                          :scope => [:parent_id],
                          :unless => Proc.new { |taxon| taxon.parent_id.nil? },
                          :message => "already used as a child of this " + 
                                      "taxon's parent"
  
  NAME_PROVIDER_TITLES = {
    'ColNameProvider' => 'Catalogue of Life',
    'UBioNameProvider' => 'uBio'
  }
  
  RANK_LEVELS = {
    'root'         => 100,
    'kingdom'      => 70,
    'phylum'       => 60,
    'subphylum'    => 57,
    'superclass'   => 53,
    'class'        => 50,
    'subclass'     => 47,
    'superorder'   => 43,
    'order'        => 40,
    'suborder'     => 37,
    'superfamily'  => 33,
    'family'       => 30,
    'subfamily'    => 27,
    'supertribe'   => 26,
    'tribe'        => 25,
    'subtribe'     => 24,
    'genus'        => 20,
    'species'      => 10,
    'subspecies'   => 5,
    'variety'      => 5,
    'form'         => 5
  }
  
  RANKS = RANK_LEVELS.keys
  
  RANK_EQUIVALENTS = {
    'division'        => 'phylum',
    'sub-class'       => 'subclass',
    'super-order'     => 'superorder',
    'infraorder'      => 'suborder',
    'sub-order'       => 'suborder',
    'super-family'    => 'superfamily',
    'sub-family'      => 'subfamily',
    'gen'             => 'genus',
    'sp'              => 'species',
    'infraspecies'    => 'subspecies',
    'ssp'             => 'subspecies',
    'sub-species'     => 'subspecies',
    'subsp'           => 'subspecies',
    'trinomial'       => 'subspecies',
    'var'             => 'variety',
    'unranked'        => nil
  }
  
  PREFERRED_RANKS = [
    'kingdom',
    'phylum',
    'class',
    'order',
    'superfamily',
    'family',
    'genus',
    'species',
    'subspecies',
    'variety'
  ]
  
  # In case you don't feel like looking up TaxonNames
  ICONIC_TAXON_NAMES = {
    'Animalia' => 'Animals',
    'Actinopterygii' => 'Ray-finned Fishes',
    'Aves' => 'Birds',
    'Reptilia' => 'Reptiles',
    'Amphibia' => 'Amphibians',
    'Mammalia' => 'Mammals',
    'Arachnida' => 'Arachnids',
    'Insecta' => 'Insects',
    'Plantae' => 'Plants',
    'Fungi' => 'Fungi',
    'Protozoa' => 'Protozoans',
    'Mollusca' => 'Mollusks'
  }
  
  ICONIC_TAXON_DISPLAY_NAMES = ICONIC_TAXON_NAMES.merge(
    'Animalia' => 'Other Animals'
  )
  
  named_scope :observed_by, lambda {|user|
    { :joins => """
      JOIN (
        SELECT
          taxon_id
        FROM
          observations
        WHERE
          user_id=#{user.id}
        GROUP BY taxon_id
      ) o
      ON o.taxon_id=#{Taxon.table_name}.#{Taxon.primary_key}
      """ }}
  
  named_scope :iconic_taxa, :conditions => "is_iconic = true",
    :include => [:taxon_names]
  
  named_scope :of_rank, lambda {|rank|
    {:conditions => ["rank = ?", rank]}
  }
  
  ICONIC_TAXA = Taxon.sort_by_ancestry(self.iconic_taxa.arrange)
  ICONIC_TAXA_BY_ID = ICONIC_TAXA.index_by(&:id)
  ICONIC_TAXA_BY_NAME = ICONIC_TAXA.index_by(&:name)
  
  
  # Callbacks ###############################################################
  
  def handle_after_move
    if ancestry_changed?
      unless new_record?
        update_listed_taxa
        update_life_lists
        update_obs_iconic_taxa
      end
      set_iconic_taxon
    end
    true
  end
  
  def normalize_rank
    self.rank = Taxon.normalize_rank(self.rank)
    true
  end
  
  def set_rank_level
    self.rank_level = RANK_LEVELS[self.rank]
    true
  end
  
  def remove_rank_from_name
    self.name = Taxon.remove_rank_from_name(self.name)
    true
  end
  
  #
  # Set the iconic taxon if it hasn't been set
  #
  def set_iconic_taxon(options = {})
    unless iconic_taxon_id_changed?
      self.iconic_taxon = if is_iconic?
        self
      else
        ancestors.reverse.select {|a| a.is_iconic?}.first
      end
    end
    
    if !new_record? && (iconic_taxon_id_changed? || options[:force])
      descendants.update_all(
        "iconic_taxon_id = #{iconic_taxon_id || 'NULL'}", 
        ["iconic_taxon_id IN (?) OR iconic_taxon_id IS NULL", ancestor_ids])
      Taxon.send_later(:set_iconic_taxon_for_observations_of, id)
    end
    true
  end
  
  def set_wikipedia_summary_later
    send_later(:set_wikipedia_summary) if wikipedia_title_changed?
    true
  end
  
  def capitalize_name
    self.name = name.capitalize
    true
  end
  
  # Create a taxon name with the same name as this taxon
  def create_matching_taxon_name
    return if @skip_new_taxon_name
    return if scientific_name
    
    taxon_attributes = self.attributes
    taxon_attributes.delete('id')
    tn = TaxonName.new
    taxon_attributes.each do |k,v|
      tn[k] = v if TaxonName.column_names.include?(k)
    end
    tn.lexicon = TaxonName::LEXICONS[:SCIENTIFIC_NAMES]
    tn.is_valid = true
    
    self.taxon_names << tn
    true
  end
  
  # /Callbacks ##############################################################
  
  
  # see the end for the validate method
  def to_s
    "<Taxon #{id}: #{to_plain_s(:skip_common => true)}>"
  end
  
  def to_plain_s(options = {})
    comname = common_name unless options[:skip_common]
    sciname = if %w(species infraspecies).include?(rank)
      name
    else
      "#{rank.capitalize} #{name}"
    end
    return sciname if comname.blank?
    "#{comname.name} (#{sciname})"
  end
  
  def observations_count_with_descendents
    Observation.of(self).count
  end
  
  #
  # Test whether this taxon's range overlaps a place
  #
  # def range_overlaps?(place)
  #   # looks like georuby doesn't support intersection just yet, probably 
  #   # because MySQL only supports intersections of minimum bounding 
  #   # rectangles.  Kinda stupid...
  #   self.range.geom.intersects? place.geom
  # end
  
  #
  # Test whether this taxon is in another taxon (e.g. Anna's Humminbird is in 
  # Class Aves)
  #
  def in_taxon?(taxon)
    # self.lft > taxon.lft && self.rgt < taxon.rgt
    ancestor_ids.include?(taxon.id)
  end
  
  def graft
    Ratatosk.graft(self)
  end
  
  def grafted?
    return false if new_record? # New records haven't been grafted
    return false if self.name != 'Life' && ancestry.blank?
    true
  end
  
  def self_and_ancestors
    [ancestors, self].flatten
  end
  
  def root?
    parent_id.nil?
  end
  
  def move_to_child_of(taxon)
    self.update_attributes(:parent => taxon)
  end
  
  def default_name
    TaxonName.choose_default_name(taxon_names)
  end
  
  def scientific_name
    TaxonName.choose_scientific_name(taxon_names)
  end
  
  #
  # Return just one common name.  Defaults to the first English common name, 
  # then first name of unspecified language (not-not-English), then the first 
  # common name of any language failing that
  #
  def common_name
    TaxonName.choose_common_name(taxon_names)
  end
  
  #
  # Create a scientific taxon name matching this taxon's name if one doesn't
  # already exist.
  #
  def set_scientific_taxon_name
    unless taxon_names.exists?(["name = ?", name])
      self.taxon_names << TaxonName.new(
        :name => name,
        :source => source,
        :source_identifier => source_identifier,
        :source_url => source_url,
        :lexicon => TaxonName::LEXICONS[:SCIENTIFIC_NAMES],
        :is_valid => true
      )
    end
  end
  
  #
  # Checks whether this taxon has been flagged
  #
  def flagged?
    self.flags.select { |f| not f.resolved? }.size > 0
  end
  
  #
  # Fetches associated user-selected FlickrPhotos if they exist, otherwise
  # gets the the first :limit Create Commons-licensed photos tagged with the
  # taxon's scientific name from Flickr.  So this will return a heterogeneous
  # array: part FlickrPhotos, part net::flickr Photos
  #
  def photos_with_backfill(options = {})
    options[:limit] ||= 9
    chosen_photos = photos.all(:limit => options[:limit])
    if chosen_photos.size < options[:limit]
      conditions = ["(taxon_photos.taxon_id = ? OR taxa.ancestry LIKE '#{ancestry}/#{id}%')", self]
      if chosen_photos.size > 0
        conditions = Taxon.merge_conditions(conditions, ["photos.id NOT IN (?)", chosen_photos])
      end
      chosen_photos += Photo.all(
        :include => [{:taxon_photos => :taxon}], 
        :conditions => conditions,
        :limit => options[:limit] - chosen_photos.size)
    end
    flickr_chosen_photos = []
    if !options[:skip_external] && chosen_photos.size < options[:limit] && self.auto_photos
      begin
        netflickr = Net::Flickr.authorize(FLICKR_API_KEY, FLICKR_SHARED_SECRET)
        flickr_chosen_photos = netflickr.photos.search({
          :tags => self.name.gsub(' ', '').strip,
          :per_page => options[:limit] - chosen_photos.size,
          :license => '1,2,3,4,5,6', # CC licenses
          :extras => 'date_upload,owner_name',
          :sort => 'relevance'
        }).to_a
      rescue Net::Flickr::APIError => e
        logger.error "EXCEPTION RESCUE: #{e}"
        logger.error e.backtrace.join("\n\t")
      end
    end
    flickr_ids = chosen_photos.map(&:native_photo_id)
    chosen_photos += flickr_chosen_photos.reject do |fp|
      flickr_ids.include?(fp.id)
    end
    chosen_photos
  end
  
  def phylum
    ancestors.find(:first, :conditions => "rank = 'phylum'")
  end
  

  def validate
    if self.parent == self
      errors.add(self.name, "can't be its own parent")
    end
    if self.ancestors and self.ancestors.include? self
      errors.add(self.name, "can't be its own ancestor")
    end
  end
  
  def indexed_self_and_ancestors(params = {})
    params = params.merge({
      :from => "`#{Taxon.table_name}` FORCE INDEX (index_taxa_on_lft_and_rgt)", 
      :conditions => ["`lft` <= ? AND `rgt` >= ?", self.lft, self.rgt]
    })
    Taxon.all(params)
  end
  
  #
  # Determine whether this taxon is at or below the rank of species
  #
  def species_or_lower?
    return false if rank.blank?
    %w"species subspecies variety infraspecies".include?(rank.downcase)
  end
  
  # Updated the "cached" lft values in all listed taxa with this taxon
  def update_listed_taxa
    ListedTaxon.update_all(
      "taxon_ancestor_ids = '#{ancestor_ids.join(',')}'", 
      "taxon_id = #{self.id}")
    true
  end
  
  def update_life_lists
    LifeList.send_later(:update_life_lists_for_taxon, self)
    true
  end
  
  def update_obs_iconic_taxa
    Observation.update_all(["iconic_taxon_id = ?", iconic_taxon_id], ["taxon_id = ?", id])
    true
  end
  
  def lsid
    "lsid:inaturalist.org:taxa:#{id}"
  end
  
  # Flagged method is called after every add_flag.  This callback method
  # is totally optional and does not have to be included in the model
  def flagged(flag, flag_count)
    true
  end
  
  def update_unique_name(options = {})
    reload # there's a chance taxon names have been created since load
    return true unless default_name
    [default_name.name, name].uniq.each do |candidate|
      # Skip if this name isn't unique
      if TaxonName.count(:select => "distinct(taxon_id)", :conditions => {:name => candidate}) > 1  
        next
      end
      begin
        logger.info "Updating unique_name for #{self} to #{candidate}"
        Taxon.update_all(["unique_name = ?", candidate], ["id = ?", self])
      rescue ActiveRecord::StatementInvalid => e
        next if e.message =~ /Duplicate entry/
        raise e
      end
      break
    end
  end
  

  def wikipedia_summary(options = {})
    if super && super.match(/^\d\d\d\d-\d\d-\d\d$/)
      last_try_date = DateTime.parse(super)
      return nil if last_try_date > 1.week.ago
    end
    return super unless super.blank? || options[:reload]
    
    send_later(:set_wikipedia_summary)
    nil
  end
  
  def set_wikipedia_summary
    w = WikipediaService.new
    summary = query_results = parsed = nil
    begin
      query_results = w.query(
        :titles => (wikipedia_title.blank? ? name : wikipedia_title),
        :redirects => '', 
        :prop => 'revisions', 
        :rvprop => 'content')
      raw = query_results.at('page')
      parsed = if raw.blank?
        nil
      else
        w.parse(:page => raw['title']).at('text').inner_text
      end
    rescue Timeout::Error => e
      logger.info "[INFO] Wikipedia API call failed while setting taxon summary: #{e.message}"
    end

    if query_results && parsed && !query_results.at('page')['missing']
      coder = HTMLEntities.new
      summary = coder.decode(parsed)
      
      hxml = Hpricot(summary)
      hxml.search('table').remove
      hxml.search('div').remove
      summary = (hxml.at('p') || hxml.at('//')).inner_html.to_s
      
      sanitizer = HTML::WhiteListSanitizer.new
      summary = sanitizer.sanitize(summary, :tags => %w(p i em b strong))
      summary.gsub! /\[.*?\]/, ''
      pre_trunc = summary
      summary = summary.split[0..75].join(' ')
      summary += '...' if pre_trunc > summary
    end
    
    if summary.blank?
      Taxon.update_all(["wikipedia_summary = ?", Date.today], ["id = ?", self])
      return nil
    end

    Taxon.update_all(["wikipedia_summary = ?", summary], ["id = ?", self])
    summary
  end
  
  def merge(reject)
    raise "Can't merge a taxon with itself" if reject.id == self.id
    
    reject_taxon_names = reject.taxon_names.all
    
    # Merge has_many associations
    has_many_reflections = Taxon.reflections.select{|k,v| v.macro == :has_many}
    has_many_reflections.each do |k, reflection|
      # Avoid those pesky :through relats
      next unless reflection.klass.column_names.include?(reflection.primary_key_name)
      reflection.klass.update_all(
        ["#{reflection.primary_key_name} = ?", id], 
        ["#{reflection.primary_key_name} = ?", reject.id]
      )
    end
    
    # Merge ListRules and other polymorphic assocs
    ListRule.update_all(["operand_id = ?", id], ["operand_id = ? AND operand_type = ?", reject.id, Taxon.to_s])
    
    # Keep reject colors if keeper has none
    self.colors << reject.colors if colors.blank?
    
    # Move reject child taxa to the keeper
    reject.children.each {|child| child.move_to_child_of(self)}
    
    # Update or destroy merged taxon_names
    reject_taxon_names.each do |taxon_name|
      taxon_name.reload
      unless taxon_name.valid?
        logger.info "[INFO] Destroying #{taxon_name} while merging taxon " + 
          "#{reject.id} into taxon #{id}: #{taxon_name.errors.full_messages.to_sentence}"
        taxon_name.destroy 
        next
      end
      if taxon_name.is_scientific_names? && taxon_name.is_valid?
        taxon_name.update_attributes(:is_valid => false)
      end
    end
    
    LifeList.send_later(:update_life_lists_for_taxon, self)
    
    reject.reload
    logger.info "[INFO] Merged #{reject} into #{self}"
    reject.destroy
  end
  
  def to_tags
    tags = []
    if grafted?
      tags += self_and_ancestors.map do |taxon|
        unless taxon.root?
          name_pieces = taxon.name.split
          name_pieces.delete('subsp.')
          if name_pieces.size == 3
            ["taxonomy:species=#{name_pieces[1]}", "taxonomy:trinomial=#{name_pieces.join(' ')}"]
          elsif name_pieces.size == 2
            ["taxonomy:species=#{name_pieces[1]}", "taxonomy:binomial=#{taxon.name.strip}"]
          else
            ["taxonomy:#{taxon.rank}=#{taxon.name.strip}", taxon.name.strip]
          end
        end
      end.flatten.compact
    else
      name_pieces = name.split
      name_pieces.delete('subsp.')
      if name_pieces.size == 3
        tags << "taxonomy:trinomial=#{name_pieces.join(' ')}"
        tags << "taxonomy:binomial=#{name_pieces[0]} #{name_pieces[1]}"
      elsif name_pieces.size == 2
        tags << "taxonomy:binomial=#{name.strip}"
      else
        tags << "taxonomy:#{rank}=#{name.strip}"
      end
    end
    tags += taxon_names.map{|tn| tn.name.strip if tn.is_valid?}.compact
    tags += taxon_names.map do |taxon_name|
      unless taxon_name.lexicon == TaxonName::LEXICONS[:SCIENTIFIC_NAMES]
        "taxonomy:common=#{taxon_name.name.strip}"
      end
    end.compact.flatten
    
    tags.compact.flatten.uniq
  end
  
  def parent_id=(parent_id)
    return unless !parent_id.blank? && Taxon.find_by_id(parent_id)
    super
  end
  
  include TaxaHelper
  def image_url
    taxon_image_url(self)
  end
  
  # Static ##################################################################
  
  #
  # Count the number of taxa in the given rank.
  #
  # I don't like hard-coding it like this, so if you know an abstract way of 
  # getting at the column name associated with an attribute, or an aliased 
  # attribute like 'rank', please tell me.
  #
  def self.count_taxa_in_rank(rank)
    Taxon.count_by_sql(
      "SELECT COUNT(*) from #{Taxon.table_name} WHERE (rank = '#{rank.downcase}')"
    )
  end
  
  def self.normalize_rank(rank)
    return rank if rank.nil?
    rank = rank.gsub(/[^\w]/, '').downcase
    return rank if RANKS.include?(rank)
    return RANK_EQUIVALENTS[rank] if RANK_EQUIVALENTS[rank]
    rank
  end
  
  def self.remove_rank_from_name(name)
    pieces = name.split
    return name if pieces.size == 1
    pieces.map! {|p| p.gsub('.', '')}
    pieces.reject! {|p| (RANKS + RANK_EQUIVALENTS.keys).include?(p.downcase)}
    pieces.join(' ')
  end
  
  # Convert an array of strings to taxa
  def self.tags_to_taxa(tags)
    taxon_names = tags.map do |tag|
      if matches = tag.match(/^taxonomy:\w+=(.*)/)
        TaxonName.find_by_name(matches[1])
      else
        TaxonName.find_by_name(tag)
      end
    end.compact
    taxon_names.map(&:taxon).compact
  end
  
  def self.find_duplicates
    duplicate_counts = Taxon.count(:group => "name", :having => "count_all > 1")
    num_keepers = 0
    num_rejects = 0
    for name in duplicate_counts.keys
      taxa = Taxon.all(:conditions => ["name = ?", name])
      logger.info "[INFO] Found #{taxa.size} duplicates for #{name}: #{taxa.map(&:id).join(', ')}"
      taxa.group_by(&:parent_id).each do |parent_id, child_taxa|
        logger.info "[INFO] Found #{child_taxa.size} duplicates within #{parent_id}: #{child_taxa.map(&:id).join(', ')}"
        next unless child_taxa.size > 1
        child_taxa = child_taxa.sort_by(&:id)
        keeper = child_taxa.shift
        child_taxa.each {|t| keeper.merge(t)}
        num_keepers += 1
        num_rejects += child_taxa.size
      end
    end
    
    logger.info "[INFO] Finished Taxon.find_duplicates.  Kept #{num_keepers}, removed #{num_rejects}."
  end
  
  def self.rebuild_without_callbacks
    ThinkingSphinx.deltas_enabled = false
    before_validation.clear
    before_save.clear
    after_save.clear
    validates_associated.clear
    validates_presence_of.clear
    validates_uniqueness_of.clear
    restore_ancestry_integrity!
    ThinkingSphinx.deltas_enabled = true
  end
  
  # Do something without all the callbacks.  This disables all callbacks and
  # validations and doesn't restore them, so IT SHOULD NEVER BE CALLED BY THE
  # APP!  The process should end after this is done.
  def self.without_callbacks(&block)
    ThinkingSphinx.deltas_enabled = false
    before_validation.clear
    before_save.clear
    after_save.clear
    validates_associated.clear
    validates_presence_of.clear
    validates_uniqueness_of.clear
    yield
  end
  
  def self.set_iconic_taxon_for_observations_of(taxon)
    taxon = Taxon.find_by_id(taxon) unless taxon.is_a?(Taxon)
    return unless taxon
    Observation.update_all(
      "iconic_taxon_id = #{taxon.iconic_taxon_id || 'NULL'}",
      ["taxon_id = ?", taxon.id]
    )
    
    taxon.descendants.find_each(:conditions => "observations_count > 0") do |descendant|
      Observation.update_all(
        "iconic_taxon_id = #{taxon.iconic_taxon_id || 'NULL'}",
        ["taxon_id = ?", descendant.id]
      )
    end
  end
  
  def self.occurs_in(minx, miny, maxx, maxy, startdate=nil, enddate=nil)
    startdate = startdate.nil? ? 100.years.ago.to_date : Date.parse(startdate) # wtf, only 100 years?!
    enddate = enddate.nil? ? Time.now.to_date : Date.parse(enddate)
    startdate = startdate.to_param
    enddate = enddate.to_param
    sql = """
      SELECT 
        t.*,
        o.count as count
      FROM
        col_taxa t
          JOIN 
            (SELECT 
                taxon_id, count(*) as count
              FROM observations 
              WHERE 
                observed_on > '#{startdate}' AND observed_on < '#{enddate}' AND
                latitude > '#{miny}' AND 
                longitude > '#{minx}' AND 
                latitude < '#{maxy}' AND 
                longitude < '#{maxx}'
              GROUP BY taxon_id) o
            ON o.taxon_id=t.record_id
    """
    Taxon.find_by_sql(sql)
  end
  
  # /Static #################################################################
  
end
