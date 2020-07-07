import React from "react";
import PropTypes from "prop-types";
import { Button } from "react-bootstrap";
import TaxonAutocomplete from "../../../shared/components/taxon_autocomplete";
import INatTextArea from "./inat_text_area";

const IdentificationForm = ( {
  observation: o,
  onSubmitIdentification,
  className,
  blind,
  key
} ) => (
  <form
    key={key}
    className={`IdentificationForm ${className}`}
    onSubmit={function ( e ) {
      e.preventDefault();
      // Note that data( "uiAutocomplete" ).selectedItem seems to disappear when
      // you re-focus on the taxon field, which can lead to some confusion b/c
      // it still looks like the taoxn is selected in that state
      const idTaxon = $( ".IdentificationForm:visible:first input[name='taxon_name']" ).data( "autocomplete-item" );
      if ( !idTaxon ) {
        return;
      }
      const isDisagreement = ( ) => {
        if ( !o || !( o.community_taxon || o.taxon ) ) {
          return false;
        }
        let observationTaxon = o.taxon;
        if (
          o.preferences.prefers_community_taxon === false
          || o.user.preferences.prefers_community_taxa === false
        ) {
          observationTaxon = o.community_taxon || o.taxon;
        }
        return observationTaxon.id !== idTaxon.id
          && observationTaxon.ancestor_ids.indexOf( idTaxon.id ) > 0;
      };
      const params = {
        observation_id: o.id,
        taxon_id: idTaxon.id,
        body: e.target.elements.body.value,
        blind
      };
      if ( blind && isDisagreement( ) && e.target.elements.disagreement ) {
        params.disagreement = e.target.elements.disagreement.value === "1";
      }
      onSubmitIdentification( params, {
        observation: o,
        taxon: idTaxon,
        potentialDisagreement: !blind && isDisagreement( )
      } );
      // this doesn't feel right... somehow submitting an ID should alter
      // the app state and this stuff should flow three here as props
      $( "input[name='taxon_name']", e.target ).trigger( "resetAll" );
      $( "input[name='taxon_name']", e.target ).blur( );
      $( e.target.elements.body ).val( null );
    }}
  >
    <h3>{ I18n.t( "add_an_identification" ) }</h3>
    <TaxonAutocomplete bootstrapClear />
    <INatTextArea
      type="textarea"
      name="body"
      className="form-control"
      elementKey={`${key}-inat-text-area`}
      mentions
    />
    { blind ? (
      <div className="form-group disagreement-group">
        <label>
          <input
            type="radio"
            name="disagreement"
            value="0"
            defaultChecked
          />
          { " " }
          Others could potentially refine this ID
        </label>
        <label>
          <input type="radio" name="disagreement" value="1" />
          { " " }
          This is the most specific ID the evidence justifies
        </label>
      </div>
    ) : null }
    <Button type="submit" bsStyle="success">{ I18n.t( "save" ) }</Button>
  </form>
);

IdentificationForm.propTypes = {
  observation: PropTypes.object,
  onSubmitIdentification: PropTypes.func.isRequired,
  className: PropTypes.string,
  blind: PropTypes.bool,
  key: PropTypes.string
};

export default IdentificationForm;
