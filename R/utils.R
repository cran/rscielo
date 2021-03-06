# Function to extract meta-data from an article
get_xml_article <- function(link) {


  # Read tge page
  page <- try(xml2::read_xml(link), silent = T)
  if(class(page)[1] == "try-error") return(rep(NA, 13))

  lastname <- extract_node(page, "//article-meta/contrib-group/contrib/name/surname")
  firstname <- extract_node(page, "//article-meta/contrib-group/contrib/name/given-names")
  institution <- extract_node(page, "//article-meta/aff/institution")
  adress <- extract_node(page, "//article-meta/aff/addr-line")
  country <- extract_node(page, "//article-meta/aff/country")
  title <- extract_node(page, "//article-meta/title-group/article-title")
  year <- extract_node(page, "//article-meta/pub-date/year")
  journal <- extract_node(page, "//journal-title")
  volume <- extract_node(page, "//article-meta/volume")
  number <- extract_node(page, "//article-meta/numero")
  abstract_pt <- extract_node(page, "//article-meta/abstract[@xml:lang='pt']/p")
  abstract_en <- extract_node(page, "//article-meta/abstract[@xml:lang='en']/p")
  abstract_es <- extract_node(page, "//article-meta/abstract[@xml:lang='es']/p")
  keywords_pt <- extract_node(page, "//article-meta/kwd-group/kwd[@lng='pt']")
  keywords_en <- extract_node(page, "//article-meta/kwd-group/kwd[@lng='en']")
  keywords_es <- extract_node(page, "//article-meta/kwd-group/kwd[@lng='es']")
  f_pag <- extract_node(page, "//article-meta/fpage") %>% as.numeric()
  l_pag <- extract_node(page, "//article-meta/lpage") %>% as.numeric()
  n_refs <- extract_node(page, "//ref-list/ref") %>% length()
  doi <- extract_node(page, "//article-meta/article-id[@pub-id-type = 'doi']")
  article_id  <- extract_node(page, "//article-meta/article-id[1]")

  tibble::tibble(author = paste(firstname, lastname, collapse = "; ") %>% utf8(),
                 first_author_surname = lastname[1] %>% utf8(),
                 institution = paste(institution, collapse = "; ") %>% utf8(),
                 inst_adress = paste(adress, collapse = "; ") %>% utf8(),
                 country = paste(country, collapse = "; ") %>% utf8(),
                 title = utf8(title[1]),
                 year = year[1],
                 journal = utf8(journal),
                 volume = volume,
                 number = number,
                 first_page = f_pag,
                 last_page = l_pag,
                 abstract_pt = utf8(abstract_pt),
                 abstract_en = utf8(abstract_en),
                 abstract_es = utf8(abstract_es),
                 keywords_pt = paste(keywords_pt, collapse = "; ") %>% utf8(),
                 keywords_en = paste(keywords_en, collapse = "; ") %>% utf8(),
                 keywords_es = paste(keywords_es, collapse = "; ") %>% utf8(),
                 doi = doi,
                 article_id = article_id,
                 n_authors = length(firstname),
                 n_pages = l_pag - f_pag,
                 n_refs = n_refs)
}



# Function to extract XML nodes
extract_node <- function(page, path){

  nodes <- xml2::xml_find_all(page, path)
  if(length(nodes) == 0) return("")
  xml2::xml_text(nodes)
}


# Converts a character vector encoding to UTF-8
utf8 <- function(ch) iconv(ch, from = "UTF-8")


# Tests whether an object class is 'Scielo'
is.scielo <- function(x) inherits(x, "Scielo")


# id select
id_select <- function(x){

  if(stringr::str_detect(x, "http")) {

    article_id <- stringr::str_split(x, "=|&", simplify = T)[, 4]

  } else {

    article_id <- x
  }

  return(article_id)
}



# First strategy to extract article text
get_article_strategy1 <- function(page){

  rvest::html_nodes(page, xpath = "//div[@id='article-body']//p|//div[@id='S01-body']//p") %>%
    rvest::html_text()
}



# Second strategy to extract article text
get_article_strategy2 <- function(page){


  # Test cases
  test_strategy2 <- rvest::html_nodes(page, xpath = "//hr")

  if(length(test_strategy2) == 1) {

    # Third strategy
    metodo <- 3 # tirar
    text <- get_article_strategy3(page)

  } else {

    metodo <- 2 # tirar
    xpathScieloPatterns <- c("//div[@class='content']/div/font/p",
                             "//div[@class='content']/div/font/p/preceding-sibling::comment()",
                             "//div[@class='content']/div/font/p/comment()",
                             "//div[@class='content']/div/p",
                             "//div[@class='content']/div/p/preceding-sibling::comment()",
                             "//div/hr")

    # Get data
    nodes <- page %>%
      rvest::html_nodes(xpath = paste(xpathScieloPatterns, collapse ="|"))

    tag_names <- purrr::map(nodes, rvest::html_tag) %>%
      unlist()

    complete_content <- nodes[(dplyr::last(which(tag_names=="hr"))+1):length(nodes)] %>%
      rvest::html_text()

    references_location <- grep(x = complete_content, pattern = "[[:blank:]]ref[[:blank:]]")

    if(length(references_location)>0) {

      text <- complete_content[1:(dplyr::first(references_location) - 2)]

    } else {

      text <- complete_content[-length(complete_content)]
    }

    text <- paste(text, collapse = " \n ")
  }

  list(text = text, metodo = metodo)
}



# Third strategy to extract article text
get_article_strategy3 <- function(page){


  xpathScieloPatterns <- c("//div[@class='content']/div/font/p/..",
                           "//div[@class='content']/div/font/p/../preceding-sibling::comment()",
                           "//div[@class='content']/div/font/p/../comment()",
                           "//div[@class='content']/div/p/font",
                           "//div[@class='content']/div/p/font/preceding-sibling::comment()",
                           "//div[@class='content']/div//preceding-sibling::comment()")

  font_nodes <- page %>%
    rvest::html_nodes(xpath = paste(xpathScieloPatterns, collapse="|"))

  if(length(font_nodes) < 3) {

    text <- page %>%
      rvest::html_nodes(xpath = "//p[@align = 'left']") %>%
      rvest::html_text() %>%
      paste(collapse = " \n ")

  } else {

    # Finding which font size is the most used
    font_sizes <- purrr::map(font_nodes,

                             function(x) {

                               size_attribute <- rvest::html_attr(x, "size")

                               if(length(size_attribute) == 0){

                                 size_attribute <- ""
                                 }

                               size_attribute
                               }
                             ) %>%
      unlist() %>%
      as.numeric()

    font_sizes_table <- table(font_sizes) %>%
      dplyr::as_tibble() %>%
      dplyr::arrange(-dplyr::n())

    font_1stUsed <- font_sizes_table %>%
      dplyr::filter(dplyr::n() >= 2) %>%
      .$font_sizes %>%
      purrr::pluck(1) %>%
      as.numeric()

    font_2ndUsed <- font_sizes_table %>%
      dplyr::filter(dplyr::n() >= 2) %>%
      .$font_sizes %>%
      purrr::pluck(2) %>%
      as.numeric()

    text_start <- dplyr::first(which(font_sizes == font_1stUsed))

    if(!is.na(font_2ndUsed)){

      ref_start  <- dplyr::last(which(font_sizes  == font_2ndUsed))

      text_data <- font_nodes[text_start : (ref_start - 1)] %>%
        rvest::html_text() %>%
        tibble::tibble(text = .)%>%
        dplyr::filter(dplyr::row_number() > 3 | nchar(text) > 50)

    } else {

      text_data <- font_nodes[text_start : length(font_nodes)] %>%
        rvest::html_text() %>%
        stringr::str_replace_all(pattern = "[[:punct:]][[:blank:]]{0,2}Links?[[:blank:]]{0,2}[[:punct:]]",
                        replacement = "") %>%
        stringr::str_trim() %>%
        tibble::tibble(text = .) %>%
        dplyr::filter(nchar(text) > 50)

      references <- page %>%
        rvest::html_nodes(xpath = "//comment()/ancestor::p|//comment()/ancestor::font") %>%
        rvest::html_text() %>%
        stringr::str_replace_all(pattern = "[[:punct:]][[:blank:]]{0,2}Links?[[:blank:]]{0,2}[[:punct:]]",
                        replacement = "") %>%
        stringr::str_trim() %>%
        tibble::tibble(text = .)

      if(nrow(references) > 0 ) {

        references$test <- 1

        text_data <- dplyr::left_join(text_data, references, by = "text")

        min_line <- text_data %>%
          dplyr::left_join(dplyr::mutate(line = 1:dplyr::n())) %>%
          dplyr::left_join(dplyr::filter(!is.na(.$test))) %>%
          .$line %>%
          min()

        text_data <- text_data[1:(min_line - 1), "text"]
      }

      font_nodes
    }

    header_data <-
      rvest::html_nodes(page, xpath = "//blockquote//descendant-or-self::b//ancestor-or-self::blockquote//p") %>%
      rvest::html_text() %>%
      tibble::tibble(text = .)

    text <- dplyr::anti_join(text_data, header_data) %>%
      .$text %>%
      paste(collapse = " \n ")
  }

  text
}


# Avoid the R CMD check note about magrittr's dot
utils::globalVariables(".")
