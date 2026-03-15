package com.amazon.sample.ui.web;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;
import java.util.concurrent.TimeUnit;
import java.util.regex.Pattern;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ClassPathResource;
import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.Resource;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;

@Controller
public class ProductImageController {

  private static final String CLASSPATH_PRODUCTS_DIR =
    "static/assets/img/products/";
  private static final String FALLBACK_IMAGE = "pic1.jpg";
  private static final Pattern LEGACY_UUID_IMAGE = Pattern.compile(
    "(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\.jpg$"
  );
  private static final List<String> WARHAMMER_IMAGES = List.of(
    "Intercessor_squad_space_marines_primaris_intercessors.jpg",
    "Terminator_squad_space_marines_terminator_squad.jpg",
    "Redemptor_dreadnought.jpg",
    "Captain_in_gravis_armour.jpg",
    "Bladeguard_veterans.jpg",
    "Primaris_chaplain.jpg",
    "Chaos_space_marines.jpg",
    "Daemon_prince.jpg",
    "Abaddon_the_despoiler.jpg",
    "Possessed.jpg",
    "Chaos_terminators.jpg",
    "Ork_boyz.jpg",
    "Necron_warriors.jpg",
    "Tyranid_termagants.jpg",
    "T'au_fire_warriors.jpg",
    "Eldar_guardians.jpg",
    "Citadel_base_paint_set.jpg",
    "Shade_paint_set.jpg",
    "Contrast_paint_set.jpg",
    "Dry_paint_set.jpg",
    "Technical_paint_set.jpg",
    "Citadel_mouldline_remover.jpg",
    "Citadel_plastic_glue.jpg",
    "Citadel_fine_detail_cutters.jpg",
    "Starter_brush_set.jpg",
    "Citadel_painting_handle.jpg",
    "Warhammer_40K_core_rules.jpg",
    "Codex_space_marines.jpg",
    "Codex_chaos_space_marines.jpg",
    "Combat_patrol_space_marines.jpg",
    "Combat_patrol_tyranids.jpg",
    "Aegis_defence_line.jpg",
    "Sector_mechanicus_ruins.jpg",
    "Battlezone_fronteris.jpg",
    "Warhammer_40K_starter_set.jpg",
    "First strike_starter_set.jpg"
  );

  @Value("${retail.ui.product-images-path:}")
  private String productImagesPath;

  @GetMapping("/assets/img/products/{filename:.+}")
  public ResponseEntity<Resource> productImage(
    @PathVariable String filename
  ) {
    Resource resource = resolveImage(filename);
    if (resource == null) {
      return ResponseEntity.notFound().build();
    }

    return ResponseEntity.ok()
      .contentType(MediaType.IMAGE_JPEG)
      .cacheControl(CacheControl.maxAge(30, TimeUnit.DAYS))
      .body(resource);
  }

  private Resource resolveImage(String filename) {
    Resource external = externalImage(filename);
    if (isReadable(external)) {
      return external;
    }

    Resource classpath = new ClassPathResource(CLASSPATH_PRODUCTS_DIR + filename);
    if (isReadable(classpath)) {
      return classpath;
    }

    Resource remappedLegacy = remappedLegacyImage(filename);
    if (isReadable(remappedLegacy)) {
      return remappedLegacy;
    }

    Resource fallback = new ClassPathResource(CLASSPATH_PRODUCTS_DIR + FALLBACK_IMAGE);
    return isReadable(fallback) ? fallback : null;
  }

  private Resource remappedLegacyImage(String filename) {
    if (!LEGACY_UUID_IMAGE.matcher(filename).matches()) {
      return null;
    }

    String basename = filename.substring(0, filename.length() - 4);
    int index = Math.floorMod(basename.hashCode(), WARHAMMER_IMAGES.size());
    return new ClassPathResource(CLASSPATH_PRODUCTS_DIR + WARHAMMER_IMAGES.get(index));
  }

  private Resource externalImage(String filename) {
    if (!StringUtils.hasText(productImagesPath)) {
      return null;
    }

    Path root = Paths.get(productImagesPath).normalize();
    Path candidate = root.resolve(filename).normalize();
    if (!candidate.startsWith(root) || !Files.isReadable(candidate)) {
      return null;
    }

    return new FileSystemResource(candidate);
  }

  private boolean isReadable(Resource resource) {
    return resource != null && resource.exists() && resource.isReadable();
  }
}
