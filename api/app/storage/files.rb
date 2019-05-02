class Files < BaseStorage

  def self.store(io)
    key = SecureRandom.hex
    db[:file].insert(key: key, blob: Sequel::SQL::Blob.new(io.read))

    key
  end

  def self.read(key)
    db[:file][key: key][:blob]
  end

end