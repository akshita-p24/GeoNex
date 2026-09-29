"""
app/services/media_validation.py

Fake / Irrelevant Report Detection (Report Quality Layer).

Architecture:
    Citizen submits image
         ↓
    Image validation (format, size, metadata)
         ↓
    Keyword-based hazard relevance check on description
         ↓
    Image classification (if ML model available)
         ↓
    Confidence score
         ↓
    Report classification:
        RELEVANT_HAZARD
        POSSIBLY_RELEVANT
        IRRELEVANT
        UNKNOWN

IMPORTANT:
    This system does NOT claim to perfectly detect fraud or lies.
    It detects obviously irrelevant images and flags ambiguous ones
    for Field Officer manual review.

    It does NOT automatically accuse citizens of fraud.
    Irrelevant images → LOW_CONFIDENCE + manual review flag.
    Ambiguous images → POSSIBLY_RELEVANT + manual review flag.

Classification:
    RELEVANT_HAZARD    → Normal processing queue
    POSSIBLY_RELEVANT  → Normal queue with review flag
    IRRELEVANT         → Flagged for manual review, not auto-rejected
    UNKNOWN            → Manual review (could not determine)
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional

logger = logging.getLogger(__name__)


# ============================================================
# ENUMS
# ============================================================

class MediaRelevance(str, Enum):
    RELEVANT_HAZARD = "RELEVANT_HAZARD"
    POSSIBLY_RELEVANT = "POSSIBLY_RELEVANT"
    IRRELEVANT = "IRRELEVANT"
    UNKNOWN = "UNKNOWN"


class ValidationMethod(str, Enum):
    KEYWORD_ONLY = "keyword_only"           # Description text analysis only
    IMAGE_CLASSIFIER = "image_classifier"   # ML image classification
    COMBINED = "combined"                   # Both methods
    NO_MEDIA = "no_media"                   # No media attached


# ============================================================
# RESULT
# ============================================================

@dataclass
class MediaValidationResult:
    """
    Structured result of media/report quality validation.

    Fields:
        media_relevance: Classification of media relevance to landslide hazards
        confidence: 0.0 – 1.0 confidence in the classification
        requires_manual_review: True if Field Officer should review before processing
        validation_method: Which method(s) produced this result
        reason: Human-readable explanation
        flags: List of specific issues detected
    """
    media_relevance: MediaRelevance
    confidence: float
    requires_manual_review: bool
    validation_method: ValidationMethod
    reason: str
    flags: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "media_relevance": self.media_relevance.value,
            "confidence": round(self.confidence, 3),
            "requires_manual_review": self.requires_manual_review,
            "validation_method": self.validation_method.value,
            "reason": self.reason,
            "flags": self.flags,
        }


# ============================================================
# KEYWORD LISTS
# ============================================================

# Keywords that strongly suggest landslide / geological hazard relevance.
HAZARD_KEYWORDS = {
    "landslide", "slide", "slump", "slip", "debris", "rockfall", "mudslide",
    "crack", "cracks", "fissure", "fracture", "soil", "slope", "cliff",
    "boulder", "rock", "mud", "flooding", "washout", "erosion", "collapse",
    "road", "highway", "block", "blockage", "damage", "destroyed", "broken",
    "fallen", "tree", "wall", "ground", "earth", "mountain", "hill",
    "retaining", "embankment", "scarp", "cut", "embankment", "subsidence",
    "sinkhol", "depression", "tension", "displacement", "movement",
    # Transliterations common in NER
    "bhu", "pahar", "nadi", "bandh", "tute", "tutna",
}

# Keywords that suggest clearly irrelevant content.
IRRELEVANT_KEYWORDS = {
    "book", "books", "food", "meal", "lunch", "dinner", "breakfast",
    "selfie", "face", "smile", "party", "birthday", "cake", "restaurant",
    "shopping", "clothes", "fashion", "pet", "cat", "dog", "indoor",
    "furniture", "desk", "computer", "phone", "screen", "text", "homework",
    "school", "college", "office", "meeting", "joke", "meme", "funny",
    "movie", "music", "game", "play", "sport", "cricket", "football",
    "photo", "vacation", "holiday", "trip", "tourism", "monument", "temple",
}

# Words that suggest the image is of a natural outdoor scene (neutral/possible)
OUTDOOR_NEUTRAL_KEYWORDS = {
    "outside", "outdoor", "field", "area", "location", "site", "village",
    "road", "path", "bridge", "river", "water", "rain", "forest", "jungle",
}


# ============================================================
# DESCRIPTION KEYWORD ANALYSIS
# ============================================================

def _analyze_description(description: str) -> tuple[MediaRelevance, float, list[str]]:
    """
    Analyze the text description for hazard relevance.

    Returns: (relevance, confidence, flags)
    """
    flags = []
    text = description.lower().strip()
    words = set(text.replace(",", " ").replace(".", " ").split())

    hazard_hits = words & HAZARD_KEYWORDS
    irrelevant_hits = words & IRRELEVANT_KEYWORDS
    outdoor_hits = words & OUTDOOR_NEUTRAL_KEYWORDS

    has_hazard = len(hazard_hits) > 0
    has_irrelevant = len(irrelevant_hits) > 0
    has_outdoor = len(outdoor_hits) > 0
    is_very_short = len(description.strip()) < 10

    if is_very_short:
        flags.append("description_too_short")

    if has_hazard and not has_irrelevant:
        confidence = min(0.5 + 0.1 * len(hazard_hits), 0.85)
        return MediaRelevance.RELEVANT_HAZARD, confidence, flags

    if has_irrelevant and not has_hazard:
        confidence = min(0.5 + 0.1 * len(irrelevant_hits), 0.90)
        flags.append(f"irrelevant_keywords_detected: {', '.join(irrelevant_hits)}")
        return MediaRelevance.IRRELEVANT, confidence, flags

    if has_hazard and has_irrelevant:
        flags.append("mixed_keywords_detected")
        return MediaRelevance.POSSIBLY_RELEVANT, 0.45, flags

    if has_outdoor:
        return MediaRelevance.POSSIBLY_RELEVANT, 0.35, flags

    if is_very_short:
        return MediaRelevance.UNKNOWN, 0.30, flags

    # Generic description — could be anything
    return MediaRelevance.POSSIBLY_RELEVANT, 0.30, flags


# ============================================================
# MAIN VALIDATION FUNCTION
# ============================================================

def validate_report_media(
    description: str,
    has_media: bool = False,
    media_url: Optional[str] = None,
    image_bytes: Optional[bytes] = None,
) -> MediaValidationResult:
    """
    Validate the quality and relevance of a citizen report's media.

    This function runs keyword-based analysis on the description.
    If an image classifier is available in future, it will be called here.

    Args:
        description: The report's text description.
        has_media: Whether any media was attached.
        media_url: URL of uploaded media (for logging/future classifier).
        image_bytes: Raw image bytes (if available for local classification).

    Returns:
        MediaValidationResult with classification and manual review flag.
    """
    flags: list[str] = []

    if not has_media:
        # No media attached — validate description only
        relevance, confidence, desc_flags = _analyze_description(description)
        flags.extend(desc_flags)

        return MediaValidationResult(
            media_relevance=relevance,
            confidence=confidence,
            requires_manual_review=(relevance == MediaRelevance.IRRELEVANT or
                                    relevance == MediaRelevance.UNKNOWN or
                                    confidence < 0.5),
            validation_method=ValidationMethod.NO_MEDIA,
            reason="No media attached; classification based on description text only.",
            flags=flags,
        )

    # Media is present — analyze description first
    text_relevance, text_confidence, desc_flags = _analyze_description(description)
    flags.extend(desc_flags)

    # If a dedicated image classifier is available, it would run here.
    # For now, we run keyword analysis and flag uncertain cases.
    #
    # Future hook:
    #   image_relevance = await classify_image(image_bytes)
    #   combined = combine_text_and_image_results(text_relevance, image_relevance)

    image_classifier_available = False  # Set True when classifier is ready

    if not image_classifier_available:
        flags.append("image_classifier_not_available")

        # With no image classifier:
        # - RELEVANT description + media → RELEVANT_HAZARD (lower confidence)
        # - IRRELEVANT description + media → IRRELEVANT + review
        # - POSSIBLY_RELEVANT → keep as-is
        # - UNKNOWN → manual review

        if text_relevance == MediaRelevance.RELEVANT_HAZARD:
            final_relevance = MediaRelevance.RELEVANT_HAZARD
            final_confidence = text_confidence * 0.85  # Slightly lower: can't verify image
            requires_review = final_confidence < 0.6
            reason = (
                "Description contains hazard-relevant keywords. "
                "Image classifier is not available; manual verification recommended."
            )
        elif text_relevance == MediaRelevance.IRRELEVANT:
            final_relevance = MediaRelevance.IRRELEVANT
            final_confidence = text_confidence
            requires_review = True  # Always review before rejecting
            reason = (
                "Description contains keywords unrelated to geological hazards. "
                "Flagged for Field Officer review. "
                "Report is NOT automatically rejected."
            )
        elif text_relevance == MediaRelevance.POSSIBLY_RELEVANT:
            final_relevance = MediaRelevance.POSSIBLY_RELEVANT
            final_confidence = text_confidence
            requires_review = True
            reason = (
                "Description is ambiguous. "
                "Image classifier unavailable. "
                "Sent to Field Officer for review."
            )
        else:  # UNKNOWN
            final_relevance = MediaRelevance.UNKNOWN
            final_confidence = 0.25
            requires_review = True
            reason = (
                "Could not determine relevance from description. "
                "Manual review required."
            )

        return MediaValidationResult(
            media_relevance=final_relevance,
            confidence=final_confidence,
            requires_manual_review=requires_review,
            validation_method=ValidationMethod.KEYWORD_ONLY,
            reason=reason,
            flags=flags,
        )

    # Image classifier available (future path)
    return MediaValidationResult(
        media_relevance=MediaRelevance.UNKNOWN,
        confidence=0.0,
        requires_manual_review=True,
        validation_method=ValidationMethod.UNKNOWN,  # type: ignore
        reason="Classifier path not implemented.",
        flags=flags,
    )
