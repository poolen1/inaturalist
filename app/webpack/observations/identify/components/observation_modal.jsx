import React, { PropTypes } from "react";
import ReactDOM from "react-dom";
import {
  Modal,
  Button,
  OverlayTrigger,
  Popover,
  Tooltip,
  Overlay
} from "react-bootstrap";
import _ from "lodash";
import moment from "moment";
import DiscussionListContainer from "../containers/discussion_list_container";
import CommentFormContainer from "../containers/comment_form_container";
import IdentificationFormContainer from "../containers/identification_form_container";
import SuggestionsContainer from "../containers/suggestions_container";
import AnnotationsContainer from "../containers/annotations_container";
import QualityMetricsContainer from "../containers/quality_metrics_container";
import SplitTaxon from "../../../shared/components/split_taxon";
import TaxonMap from "./taxon_map";
import UserText from "../../../shared/components/user_text";
import ZoomableImageGallery from "./zoomable_image_gallery";

import { TABS } from "../actions/current_observation_actions";

class ObservationModal extends React.Component {
  componentDidUpdate( prevProps ) {
    // this is a stupid hack to get the google map to render correctly if it
    // was created while it wasn't visible
    if ( this.props.tab === "info" && prevProps.tab !== "info" ) {
      const that = this;
      setTimeout( ( ) => {
        const map = $( ".TaxonMap", ReactDOM.findDOMNode( that ) ).data( "taxonMap" );
        google.maps.event.trigger( map, "resize" );
        if ( this.props.observation && this.props.observation.latitude ) {
          map.setCenter( new google.maps.LatLng(
            this.props.observation.latitude,
            this.props.observation.longitude
          ) );
        }
      }, 500 );
    }
  }
  render( ) {
    const {
      onClose,
      observation,
      visible,
      toggleReviewed,
      toggleCaptive,
      reviewedByCurrentUser,
      captiveByCurrentUser,
      images,
      commentFormVisible,
      identificationFormVisible,
      addIdentification,
      addComment,
      loadingDiscussionItem,
      agreeWithCurrentObservation,
      currentUserIdentification,
      showNextObservation,
      showPrevObservation,
      agreeingWithObservation,
      blind,
      tab,
      chooseTab,
      controlledTerms,
      imagesCurrentIndex,
      setImagesCurrentIndex,
      keyboardShortcutsShown,
      toggleKeyboardShortcuts
    } = this.props;
    if ( !observation ) {
      return <div></div>;
    }

    // skipping map until we can work out the memory issues
    let taxonMap;
    if ( observation.latitude ) {
      // Select a small set of attributes that won't change wildy as the
      // observation changes.
      const obsForMap = _.pick( observation, [
        "id",
        "species_guess",
        "latitude",
        "longitude",
        "positional_accuracy",
        "geoprivacy",
        "taxon",
        "user"
      ] );
      obsForMap.coordinates_obscured = observation.obscured;
      const taxonLayer = {
        observations: { observation_id: obsForMap.id },
        places: { disabled: true }
      };
      if ( !blind ) {
        taxonLayer.taxon = obsForMap.taxon;
        taxonLayer.gbif = { disabled: true };
      }
      taxonMap = (
        <TaxonMap
          key={`map-for-${obsForMap.id}`}
          taxonLayers={ [taxonLayer] }
          observations={[obsForMap]}
          clickable={!blind}
          zoomLevel={ observation.map_scale || 8 }
          mapTypeControl={false}
          showAccuracy
          showAllLayer={false}
          overlayMenu={false}
          zoomControlOptions={{ position: google.maps.ControlPosition.TOP_LEFT }}
        />
      );
    } else if ( observation.obscured ) {
      taxonMap = (
        <div className="TaxonMap empty">
          <i className="fa fa-map-marker" /> { I18n.t( "location_private" ) }
        </div>
      );
    } else {
      taxonMap = (
        <div className="TaxonMap empty">
          <i className="fa fa-map-marker" /> { I18n.t( "location_unknown" ) }
        </div>
      );
    }

    let photos = null;
    if ( images && images.length > 0 ) {
      photos = (
        <ZoomableImageGallery
          key={`map-for-${observation.id}`}
          items={images}
          slideIndex={imagesCurrentIndex}
          showThumbnails={images && images.length > 1}
          lazyLoad={false}
          server
          showNav={false}
          onSlide={ setImagesCurrentIndex }
        />
      );
    }
    let sounds = null;
    if ( observation.sounds && observation.sounds.length > 0 ) {
      sounds = observation.sounds.map( s => (
        <iframe
          width="100%"
          height="100"
          scrolling="no"
          frameBorder="no"
          src={`https://w.soundcloud.com/player/?url=https%3A//api.soundcloud.com/tracks/${s.native_sound_id}&auto_play=false&hide_related=false&show_comments=false&show_user=false&show_reposts=false&visual=false&show_artwork=false`}
        ></iframe>
      ) );
    }

    const scrollSidebarToForm = ( form ) => {
      const sidebar = $( form ).parents( ".ObservationModal:first" ).find( ".sidebar" );
      const target = $( form );
      $( ":input:visible:first", form ).focus( );
      $( sidebar ).scrollTo( target );
    };

    const showAgree = ( ) => {
      if ( loadingDiscussionItem ) {
        return false;
      }
      if ( !currentUserIdentification ) {
        return observation.taxon && observation.taxon.is_active;
      }
      return (
        observation.taxon &&
        observation.taxon.is_active &&
        observation.taxon.id !== currentUserIdentification.taxon.id
      );
    };

    const qualityGrade = ( ) => {
      if ( observation.quality_grade === "research" ) {
        return _.capitalize( I18n.t( "research_grade" ) );
      }
      return _.capitalize( I18n.t( observation.quality_grade ) );
    };

    const annoShortcuts = [];
    if ( tab === "annotations" ) {
      controlledTerms.forEach( ct => {
        let availableValues = ct.values;
        if ( observation.taxon ) {
          availableValues = _.filter( availableValues, v => (
            !v.valid_within_clade ||
            _.includes( observation.taxon.ancestor_ids, v.valid_within_clade )
          ) );
        }
        let valueKeyPosition = 0;
        while (
          availableValues.length !== _.uniq( availableValues.map( v =>
            v.label[valueKeyPosition].toLowerCase( ) ) ).length
        ) {
          valueKeyPosition += 1;
        }
        availableValues.forEach( v => {
          annoShortcuts.push( {
            attributeLabel: ct.label,
            valueLabel: v.label,
            keys: [ct.label[0].toLowerCase( ), v.label[valueKeyPosition].toLowerCase( )]
          } );
        } );
      } );
    }

    return (
      <Modal
        show={visible}
        onHide={onClose}
        bsSize="large"
        className={`ObservationModal ${blind ? "blind" : ""}`}
      >
        <div className="nav-buttons">
          <Button className="nav-button" onClick={ function ( ) { showPrevObservation( ); } }>
            &lsaquo;
          </Button>
          <Button className="next nav-button" onClick={ function ( ) { showNextObservation( ); } }>
            &rsaquo;
          </Button>
        </div>
        <div className="inner">
          <div className="left-col">
            <div className="obs-modal-header">
              <div className={`quality_grade pull-right ${observation.quality_grade}`}>
                { qualityGrade( ) }
              </div>
              <SplitTaxon
                taxon={observation.taxon}
                url={`/observations/${observation.id}`}
                target="_blank"
                placeholder={observation.species_guess}
                noParens
              />
            </div>
            <div className={( photos && sounds ) ? "photos sounds" : "media"}>
              { photos }
              { sounds }
            </div>
            <div className="tools">
              <div className="keyboard-shortcuts-container">
                <Button
                  bsStyle="link"
                  className="btn-keyboard-shortcuts"
                  onClick={ e => {
                    toggleKeyboardShortcuts( keyboardShortcutsShown );
                    e.preventDefault( );
                    return false;
                  }}
                >
                  <i className="fa fa-keyboard-o"></i>
                </Button>
                <Overlay
                  placement="top"
                  show={keyboardShortcutsShown}
                  container={ $( ".ObservationModal" ).get( 0 ) }
                  target={ ( ) => $( ".keyboard-shortcuts-container > .btn" ).get( 0 ) }
                >
                  <Popover title={ I18n.t( "keyboard_shortcuts" ) } id="keyboard-shortcuts-popover">
                    <table>
                      <tbody>
                        <tr className="keyboard-shortcuts">
                          <td><code>z</code></td>
                          <td>{ I18n.t( "organism_appears_captive_cultivated" ) }</td>
                        </tr>
                        <tr className="keyboard-shortcuts">
                          <td><code>r</code></td>
                          <td>{ I18n.t( "mark_as_reviewed" ) }</td>
                        </tr>
                        { blind ? null : (
                          <tr className="keyboard-shortcuts">
                            <td><code>c</code></td>
                            <td>{ _.capitalize( I18n.t( "comment" ) ) }</td>
                          </tr>
                        ) }
                        { blind ? null : (
                          <tr className="keyboard-shortcuts">
                            <td><code>a</code></td>
                            <td>{ _.capitalize( I18n.t( "agree" ) ) }</td>
                          </tr>
                        ) }
                        <tr className="keyboard-shortcuts">
                          <td><code>i</code></td>
                          <td>{ I18n.t( "add_id" ) }</td>
                        </tr>
                        <tr className="keyboard-shortcuts">
                          <td><code>SPACE</code></td>
                          <td>{ I18n.t( "zoom_photo" ) }</td>
                        </tr>
                        <tr className="keyboard-shortcuts">
                          <td><code>&larr;</code></td>
                          <td>{ I18n.t( "previous_observation" ) }</td>
                        </tr>
                        <tr className="keyboard-shortcuts">
                          <td><code>&rarr;</code></td>
                          <td>{ I18n.t( "next_observation" ) }</td>
                        </tr>
                        <tr className="keyboard-shortcuts">
                          <td><code>SHIFT</code> + <code>&larr;</code></td>
                          <td>{ I18n.t( "previous_tab" ) }</td>
                        </tr>
                        <tr className="keyboard-shortcuts">
                          <td><code>SHIFT</code> + <code>&rarr;</code></td>
                          <td>{ I18n.t( "next_tab" ) }</td>
                        </tr>
                        <tr className="keyboard-shortcuts">
                          <td><code>ALT/CMD</code> + <code>&larr;</code></td>
                          <td>{ I18n.t( "previous_photo" ) }</td>
                        </tr>
                        <tr className="keyboard-shortcuts">
                          <td><code>ALT/CMD</code> + <code>&rarr;</code></td>
                          <td>{ I18n.t( "next_photo" ) }</td>
                        </tr>
                        {
                          annoShortcuts.map( shortcut => {
                            // If you add more controlled terms, you'll need to
                            // add keys like
                            // add_plant_phenology_flowering_annotation to
                            // inaturalist.rake generate_translations_js
                            const labelKey = _.snakeCase( `add ${shortcut.attributeLabel} ${shortcut.valueLabel} annotation` );
                            return (
                              <tr className="keyboard-shortcuts">
                                <td>
                                  <code>{ shortcut.keys[0] }</code> {
                                    I18n.t( "then_keybord_sequence" )
                                  } <code>{ shortcut.keys[1] }</code>
                                </td>
                                <td>{ I18n.t( labelKey ) }</td>
                              </tr>
                            );
                          } )
                        }
                        <tr className="keyboard-shortcuts">
                          <td><code>?</code></td>
                          <td>{ I18n.t( "show_keyboard_shortcuts" ) }</td>
                        </tr>
                      </tbody>
                    </table>
                  </Popover>
                </Overlay>
              </div>
              <div>
                <OverlayTrigger
                  placement="top"
                  trigger="hover"
                  delayShow={1000}
                  overlay={
                    <Tooltip id="captive-btn-tooltip">
                      { I18n.t( "organism_appears_captive_cultivated" ) }
                    </Tooltip>
                  }
                  container={ $( "#wrapper.bootstrap" ).get( 0 ) }
                >
                  <label
                    className={
                      `btn btn-link btn-checkbox ${captiveByCurrentUser ? "checked" : ""}`
                    }
                  >
                    <input
                      type="checkbox"
                      checked={ captiveByCurrentUser }
                      onChange={function ( ) {
                        toggleCaptive( );
                      }}
                    /> { I18n.t( "captive_cultivated" ) }
                  </label>
                </OverlayTrigger>
              </div>
            </div>
          </div>
          <div className="right-col">
            <ul className="inat-tabs">
              {TABS.map( tabName => (
                <li className={tab === tabName ? "active" : ""}>
                  <a
                    href="#"
                    onClick={ e => {
                      e.preventDefault( );
                      chooseTab( tabName, { observation } );
                      return false;
                    } }
                  >
                    { I18n.t( _.snakeCase( tabName ), { defaultValue: tabName } ) }
                  </a>
                </li>
              ) ) }
            </ul>
            <div className="sidebar">
              <div className={`inat-tab info-tab ${tab === "info" ? "active" : ""}`}>
                <div className="info-tab-content">
                  <div className="info-tab-inner">
                    <div className="map-and-details">
                      { taxonMap }
                      <ul className="details">
                        <li>
                          <a href={`/people/${observation.user.login}`} target="_blank" className="user-link">
                            <i className="icon-person"></i> <span className="login">{ observation.user.login }</span>
                          </a>
                        </li>
                        <li>
                          <i className="fa fa-calendar"></i> {
                            observation.observed_on ?
                              moment( observation.time_observed_at || observation.observed_on ).format( "LLL" )
                              :
                              I18n.t( "unknown" )
                          }
                        </li>
                        <li>
                          <i className="fa fa-map-marker"></i> { observation.place_guess || I18n.t( "unknown" ) }
                        </li>
                        <li>
                          <a className="permalink" href={`/observations/${observation.id}`} target="_blank">
                            <i className="icon-link-external"></i>
                            { I18n.t( "view_observation" ) }
                          </a>
                        </li>
                      </ul>
                    </div>
                    <UserText text={observation.description} truncate={100} className="stacked observation-description" />
                    <DiscussionListContainer observation={observation} />
                    <center className={loadingDiscussionItem ? "loading" : "loading collapse"}>
                      <div className="big loading_spinner" />
                    </center>
                    <CommentFormContainer
                      observation={observation}
                      className={commentFormVisible ? "" : "collapse"}
                      ref={ function ( elt ) {
                        const domNode = ReactDOM.findDOMNode( elt );
                        if ( domNode && commentFormVisible ) {
                          scrollSidebarToForm( domNode );
                          if (
                            $( "textarea", domNode ).val() === ""
                            && $( ".IdentificationForm textarea" ).val() !== ""
                          ) {
                            $( "textarea", domNode ).val( $( ".IdentificationForm textarea" ).val( ) );
                          }
                        }
                      } }
                    />
                    <IdentificationFormContainer
                      observation={observation}
                      className={identificationFormVisible ? "" : "collapse"}
                      ref={ function ( elt ) {
                        const domNode = ReactDOM.findDOMNode( elt );
                        if ( domNode && identificationFormVisible ) {
                          scrollSidebarToForm( domNode );
                          if (
                            $( "textarea", domNode ).val() === ""
                            && $( ".CommentForm textarea" ).val() !== ""
                          ) {
                            $( "textarea", domNode ).val( $( ".CommentForm textarea" ).val( ) );
                          }
                        }
                      } }
                    />
                  </div>
                </div>
                <div className="tools">
                  <OverlayTrigger
                    placement="top"
                    delayShow={1000}
                    overlay={
                      <Tooltip id={`modal-reviewed-tooltip-${observation.id}`}>
                        { I18n.t( "mark_as_reviewed" ) }
                      </Tooltip>
                    }
                    container={ $( "#wrapper.bootstrap" ).get( 0 ) }
                  >
                    <label
                      className={
                        `btn btn-link btn-checkbox ${( observation.reviewedByCurrentUser || reviewedByCurrentUser ) ? "checked" : ""}`
                      }
                    >
                      <input
                        type="checkbox"
                        checked={ observation.reviewedByCurrentUser || reviewedByCurrentUser }
                        onChange={function ( ) {
                          toggleReviewed( );
                        }}
                      />
                      { I18n.t( "reviewed" ) }
                    </label>
                  </OverlayTrigger>
                  <OverlayTrigger
                    placement="top"
                    delayShow={1000}
                    overlay={
                      <Tooltip id={`modal-agree-tooltip-${observation.id}`}>
                        { I18n.t( "agree_with_current_taxon" ) }
                      </Tooltip>
                    }
                    container={ $( "#wrapper.bootstrap" ).get( 0 ) }
                  >
                    <Button
                      bsStyle="default"
                      disabled={ agreeingWithObservation || !showAgree( ) }
                      className="agree-btn"
                      onClick={ function ( ) {
                        agreeWithCurrentObservation( );
                      } }
                    >
                      { agreeingWithObservation ? (
                        <div className="loading_spinner" />
                      ) : (
                        <i className="fa fa-check"></i>
                      ) } { _.capitalize( I18n.t( "agree" ) ) }
                    </Button>
                  </OverlayTrigger>
                  <Button
                    bsStyle="default"
                    className="comment-btn"
                    onClick={ function ( ) { addComment( ); } }
                  >
                    <i className="fa fa-comment"></i> { _.capitalize( I18n.t( "comment" ) ) }
                  </Button>
                  <Button bsStyle="default" onClick={ function ( ) { addIdentification( ); } } >
                    <i className="icon-identification"></i> { I18n.t( "add_id" ) }
                  </Button>
                </div>
              </div>
              <div className={`inat-tab suggestions-tab ${tab === "suggestions" ? "active" : ""}`}>
                <SuggestionsContainer />
              </div>
              <div className={`inat-tab annotations-tab ${tab === "annotations" ? "active" : ""}`}>
                <AnnotationsContainer />
              </div>
              <div className={`inat-tab data-quality-tab ${tab === "data-quality" ? "active" : ""}`}>
                <QualityMetricsContainer />
              </div>
            </div>
          </div>
        </div>
      </Modal>
    );
  }
}

ObservationModal.propTypes = {
  onClose: PropTypes.func.isRequired,
  observation: PropTypes.object,
  visible: PropTypes.bool,
  toggleReviewed: PropTypes.func,
  toggleCaptive: PropTypes.func,
  reviewedByCurrentUser: PropTypes.bool,
  captiveByCurrentUser: PropTypes.bool,
  images: PropTypes.array,
  imagesCurrentIndex: PropTypes.number,
  commentFormVisible: PropTypes.bool,
  identificationFormVisible: PropTypes.bool,
  addIdentification: PropTypes.func,
  addComment: PropTypes.func,
  loadingDiscussionItem: PropTypes.bool,
  agreeWithCurrentObservation: PropTypes.func,
  currentUserIdentification: PropTypes.object,
  showNextObservation: PropTypes.func,
  showPrevObservation: PropTypes.func,
  agreeingWithObservation: PropTypes.bool,
  blind: PropTypes.bool,
  tab: PropTypes.string,
  chooseTab: PropTypes.func,
  controlledTerms: PropTypes.array,
  setImagesCurrentIndex: PropTypes.func,
  keyboardShortcutsShown: PropTypes.bool,
  toggleKeyboardShortcuts: PropTypes.func
};

ObservationModal.defaultProps = {
  controlledTerms: [],
  imagesCurrentIndex: 0
};

export default ObservationModal;
