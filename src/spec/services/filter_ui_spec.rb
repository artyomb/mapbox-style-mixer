require 'spec_helper'

RSpec.describe 'Filter UI Support' do
  let(:style_mixer) { StyleMixer.new }
  
  describe 'complex filter structure support' do
    it 'prefixes all filter fields consistently' do
      test_style = {
        'metadata' => {
          'filters' => {
            'airports' => [{
              'id' => 'civil_land_ad',
              'group_id' => 'airports',
              'icon' => 'civil_land_ad',
              'type' => 'AH',
              'filter' => ['==', 'type', 'AH']
            }]
          }
        }
      }
      
      mixed_style = { 'metadata' => { 'filters' => {} } }
      style_mixer.send(:merge_filters, mixed_style, test_style, 'test_prefix')
      
      result_filter = mixed_style['metadata']['filters']['test_prefix_airports'][0]
      
      expect(result_filter['id']).to eq('test_prefix_civil_land_ad')
      expect(result_filter['group_id']).to eq('test_prefix_airports')
      expect(result_filter['icon']).to eq('test_prefix_civil_land_ad')
      expect(result_filter['type']).to eq('test_prefix_AH')
      expect(result_filter['filter']).to eq(['==', 'type', 'AH'])
    end
    
    it 'preserves filters without group_id as nil' do
      test_style = {
        'metadata' => {
          'filters' => {
            'tracks' => [
              { 'id' => 'route_segments_line_high', 'icon' => 'track' },
              { 'id' => 'route_segments_line_low', 'icon' => 'track' }
            ]
          }
        }
      }
      
      mixed_style = { 'metadata' => { 'filters' => {} } }
      style_mixer.send(:merge_filters, mixed_style, test_style, 'tracks_prefix')
      
      result_filters = mixed_style['metadata']['filters']['tracks_prefix_tracks']
      
      expect(result_filters[0]['id']).to eq('tracks_prefix_route_segments_line_high')
      expect(result_filters[0]['group_id']).to be_nil
      expect(result_filters[0]['icon']).to eq('tracks_prefix_track')
      
      expect(result_filters[1]['id']).to eq('tracks_prefix_route_segments_line_low')
      expect(result_filters[1]['group_id']).to be_nil
      expect(result_filters[1]['icon']).to eq('tracks_prefix_track')
    end
    
    it 'handles filters without additional fields' do
      simple_style = {
        'metadata' => {
          'filters' => {
            'basic' => [{ 'id' => 'simple_filter', 'group_id' => 'basic' }]
          }
        }
      }
      
      mixed_style = { 'metadata' => { 'filters' => {} } }
      style_mixer.send(:merge_filters, mixed_style, simple_style, 'simple_prefix')
      
      result_filter = mixed_style['metadata']['filters']['simple_prefix_basic'][0]
      
      expect(result_filter['id']).to eq('simple_prefix_simple_filter')
      expect(result_filter['group_id']).to eq('simple_prefix_basic')
      expect(result_filter.keys).to contain_exactly('id', 'group_id')
    end
    
    it 'correctly prefixes filter_id in layers' do
      test_style = {
        'layers' => [{
          'id' => 'test_layer',
          'metadata' => { 'filter_id' => 'test_filter' }
        }]
      }
      
      mixed_style = { 'layers' => [] }
      style_mixer.send(:merge_layers, mixed_style, test_style, 'layer_prefix')
      
      result_layer = mixed_style['layers'][0]
      
      expect(result_layer['id']).to eq('layer_prefix_test_layer')
      expect(result_layer['metadata']['filter_id']).to eq('layer_prefix_test_filter')
    end
  end
end 