### calameo2pdf ---                    -*- mode: ruby; -*-

## Copyright (C) 2024  damienpichard

## Author: damienpichard <damienpichard@tutanota.de>

## This program is free software; you can redistribute it and/or modify
## it under the terms of the GNU General Public License as published by
## the Free Software Foundation, either version 3 of the License, or
## (at your option) any later version.

## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.

## You should have received a copy of the GNU General Public License
## along with this program.  If not, see <http://www.gnu.org/licenses/>.

### Code:




require 'optparse'
require 'fileutils'

require 'combine_pdf'
require 'ffi-libarchive'
require 'tty-progressbar'
require 'open-uri'
require 'nokogiri'


require_relative "String+Extension.rb"
require_relative "File+Extension.rb"




class Calameo2Pdf
  def initialize
    $program_name  = File.basename($0)
    $tmp_directory = "#{Dir.getwd}/.tmp"

    OptionParser.new do |parser|
      parser.banner  = "Usage: #{$program_name} [options] <URL>"

      parser.on("-k", "--keep", "Keep intermediary files") do |keep|
        @keep = keep
      end

      parser.on("-v", "--verbose", "Make operations more talkative") do |verbose|
        @verbose = verbose
      end

      parser.on("-h", "--help", "Prints this help") do
        puts parser
        exit
      end
    end.parse!

    @url = ARGV[0]
  end

  def parse
    page = Nokogiri::HTML(URI.open(@url))
    page.css("meta[property=og\\:image]").select { |content| @link   = File.dirname(content['content']) }
    page.css("meta[property=og\\:title]").select { |content| @title  = content['content']}
    page.css("meta[name=description]").select    { |content| @length = content['content'].between("Length: ", "pages,").to_i }
  end

  def download
    progress = TTY::ProgressBar.new("Downloading [:bar :percent]", total: @length)

    Dir.mkdir($tmp_directory)

    for i in 1..@length
      url  = "#{@link}/p#{i}.svgz"
      save = "%03d.svgz" % [i]

      File.open("#{$tmp_directory}/#{save}", 'wb') do |file|
        file << URI.open(url).read
      end

      progress.advance if @verbose
    end

    progress.finish if @verbose
  end

  def convert
    progress = TTY::ProgressBar.new("Converting  [:bar :percent]", total: @length)

    Dir.foreach($tmp_directory).sort.each do |file|
      next if     File.exclude?(file)
      next unless File.extname(file) == ".svgz"

      filepath = File.expand_path("#{$tmp_directory}/#{file}")
      savepath = "#{filepath}.pdf"

      progress.advance if @verbose
      `svg2pdf #{filepath} #{savepath} >/dev/null 2>&1`
    end

    progress.finish if @verbose
  end

  def merge()
    progress = TTY::ProgressBar.new("merging     [:bar :percent]", total: @length)
    pdf = CombinePDF.new

    Dir.foreach($tmp_directory).sort.each do |file|
      next if     File.exclude?(file)
      next unless File.extname(file) == ".pdf"

      path = File.expand_path("#{$tmp_directory}/#{file}")
      pdf << CombinePDF.load(path)

      progress.advance if @verbose
    end

    path = File.expand_path("#{$tmp_directory}/#{@title}.pdf")
    pdf.save(path)

    `gs -sDEVICE=pdfwrite -dNOPAUSE -dQUIET -dBATCH -dPDFSETTINGS=/printer -dCompatibilityLevel=1.7 -sOutputFile="#{@title}.pdf" "#{path}"`
    progress.finish if @verbose
  end


  def delete()
    FileUtils.rm_r($tmp_directory) unless @keep
  end
end




calameo = Calameo2Pdf.new
calameo.parse
calameo.download
calameo.convert
calameo.merge
calameo.delete
