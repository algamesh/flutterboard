import os
import geopandas as gpd

def convert_shapefiles_to_geojson(
    shp_directory='assets/shapefiles',
    geojson_directory='assets/geojsons'
):
    """
    Recursively looks for all .shp files under `shp_directory` (including
    subdirectories) and writes them as GeoJSON to `geojson_directory`.
    """
    # Ensure the output directory exists
    os.makedirs(geojson_directory, exist_ok=True)

    # Walk through every directory and subdirectory under shp_directory
    for root, dirs, files in os.walk(shp_directory):
        for file in files:
            if file.lower().endswith('.shp'):
                # Full path to the current shapefile
                shp_path = os.path.join(root, file)

                # Use GeoPandas to read the shapefile
                gdf = gpd.read_file(shp_path)

                # Replace the .shp extension with .geojson
                geojson_filename = file.replace('.shp', '.geojson')
                # Create the final path in geojson_directory
                geojson_path = os.path.join(geojson_directory, geojson_filename)

                # Write out to GeoJSON
                gdf.to_file(geojson_path, driver='GeoJSON')
                print(f"Converted {shp_path} -> {geojson_path}")

if __name__ == '__main__':
    convert_shapefiles_to_geojson()
